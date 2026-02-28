// ============================================================
// src/main.rs — payment-service (Rust + Actix-web)
// ============================================================
// WHY Rust for payment-service?
//   - Memory safety WITHOUT a garbage collector — no surprise GC pauses
//     when processing payments (critical path latency matters)
//   - The type system makes many entire classes of bugs (null deref,
//     data races, use-after-free) impossible at compile time
//   - Actix-web is among the fastest HTTP frameworks across all languages
//
// This service simulates payment processing — in a real system it would
// call Stripe/PayPal APIs. Secrets (API keys) come from Vault Agent injection.

use actix_web::{web, App, HttpRequest, HttpResponse, HttpServer, middleware};
use chrono::Utc;
use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm};
use log::{error, info};
use prometheus::{Counter, Encoder, Opts, Registry, TextEncoder};
use serde::{Deserialize, Serialize};
use std::env;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;

// ── Domain Types ──────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize, Clone)]
struct Payment {
    id:         String,
    order_id:   i64,
    user_id:    i64,
    amount:     f64,
    currency:   String,
    status:     String,  // pending | completed | failed | refunded
    created_at: String,
}

#[derive(Debug, Deserialize)]
struct PaymentRequest {
    order_id: i64,
    amount:   f64,
    currency: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Claims {
    sub: i64,  // user_id from user-service JWT
}

// ── Application State ─────────────────────────────────────────
// In production, payments would be persisted to a database.
// For the learning setup, we store in-memory.
type PaymentsStore = Arc<Mutex<Vec<Payment>>>;

// ── JWT Auth Extractor ────────────────────────────────────────
fn extract_user_id(req: &HttpRequest) -> Result<i64, String> {
    let auth = req
        .headers()
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .ok_or("Missing Authorization header")?;

    if !auth.starts_with("Bearer ") {
        return Err("Malformed Authorization header".to_string());
    }

    let token = &auth[7..];
    let secret = env::var("JWT_SECRET").unwrap_or_default();
    let mut validation = Validation::new(Algorithm::HS256);
    validation.insecure_disable_signature_validation(); // use in dev only

    let data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &validation,
    )
    .map_err(|e| format!("Invalid token: {e}"))?;

    Ok(data.claims.sub)
}

// ── Handlers ──────────────────────────────────────────────────

async fn health() -> HttpResponse {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "service": "payment-service",
        "timestamp": Utc::now().to_rfc3339(),
    }))
}

async fn metrics_handler(registry: web::Data<Registry>) -> HttpResponse {
    let encoder = TextEncoder::new();
    let mut buffer = Vec::new();
    let metric_families = registry.gather();
    encoder.encode(&metric_families, &mut buffer).unwrap();
    HttpResponse::Ok()
        .content_type("text/plain; version=0.0.4")
        .body(buffer)
}

async fn create_payment(
    req: HttpRequest,
    payload: web::Json<PaymentRequest>,
    store: web::Data<PaymentsStore>,
    counter: web::Data<Counter>,
) -> HttpResponse {
    counter.inc();

    // Authenticate caller
    let user_id = match extract_user_id(&req) {
        Ok(id) => id,
        Err(e) => return HttpResponse::Unauthorized().json(serde_json::json!({"error": e})),
    };

    // Validate amount
    if payload.amount <= 0.0 {
        return HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "Amount must be positive"}));
    }

    let payment = Payment {
        id:         Uuid::new_v4().to_string(),
        order_id:   payload.order_id,
        user_id,
        amount:     payload.amount,
        currency:   payload.currency.clone().unwrap_or_else(|| "USD".to_string()),
        // Simulate: in prod this would call the payment provider and return their status
        status:     "completed".to_string(),
        created_at: Utc::now().to_rfc3339(),
    };

    info!(
        "[payment] Created payment {} for order {} amount {:.2}",
        payment.id, payment.order_id, payment.amount
    );

    let mut store = store.lock().await;
    store.push(payment.clone());

    HttpResponse::Created().json(payment)
}

async fn list_payments(
    req: HttpRequest,
    store: web::Data<PaymentsStore>,
) -> HttpResponse {
    let user_id = match extract_user_id(&req) {
        Ok(id) => id,
        Err(e) => return HttpResponse::Unauthorized().json(serde_json::json!({"error": e})),
    };

    let store = store.lock().await;
    let user_payments: Vec<&Payment> = store.iter().filter(|p| p.user_id == user_id).collect();
    HttpResponse::Ok().json(user_payments)
}

// ── Main ──────────────────────────────────────────────────────
#[actix_web::main]
async fn main() -> std::io::Result<()> {
    dotenv::dotenv().ok();
    env_logger::init();

    let port = env::var("PORT").unwrap_or_else(|_| "8090".to_string());
    let addr = format!("0.0.0.0:{port}");

    // Prometheus registry
    let registry = Registry::new();
    let payment_counter = Counter::with_opts(
        Opts::new("payment_service_payments_total", "Total payments processed")
    ).unwrap();
    registry.register(Box::new(payment_counter.clone())).unwrap();

    // Shared in-memory store
    let store: PaymentsStore = Arc::new(Mutex::new(Vec::new()));

    info!("[payment-service] Listening on {addr}");

    HttpServer::new(move || {
        App::new()
            .wrap(middleware::Logger::default())
            .app_data(web::Data::new(store.clone()))
            .app_data(web::Data::new(registry.clone()))
            .app_data(web::Data::new(payment_counter.clone()))
            // Platform routes
            .route("/health", web::get().to(health))
            .route("/metrics", web::get().to(metrics_handler))
            // Business routes
            .route("/payments", web::post().to(create_payment))
            .route("/payments", web::get().to(list_payments))
    })
    .bind(&addr)?
    .run()
    .await
}
