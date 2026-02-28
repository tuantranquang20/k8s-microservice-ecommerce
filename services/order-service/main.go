// ============================================================
// main.go — order-service Entry Point
// ============================================================
// WHY Go for order-service?
//   - Compiled binary = ~10MB Docker image (vs 200MB+ for Node/Python)
//   - Goroutines handle thousands of concurrent order requests cheaply
//   - Strong typing catches bugs at compile time, not in production
//   - Excellent concurrency primitives for publishing to Redis

package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq" // PostgreSQL driver (blank import registers it)
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/v9"
	"context"
)

// ── Global instances ──────────────────────────────────────────
var (
	db          *sql.DB
	redisClient *redis.Client

	// Prometheus counters (registered at startup)
	httpRequests = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "order_service_http_requests_total",
			Help: "Total HTTP requests to order-service",
		},
		[]string{"method", "path", "status"},
	)
)

// ── Order domain model ────────────────────────────────────────
type Order struct {
	ID         int       `json:"id"`
	UserID     int       `json:"user_id"`
	ProductID  string    `json:"product_id"` // MongoDB ObjectId (string)
	Quantity   int       `json:"quantity"`
	TotalPrice float64   `json:"total_price"`
	Status     string    `json:"status"` // pending | confirmed | shipped | delivered
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type CreateOrderRequest struct {
	ProductID  string  `json:"product_id" binding:"required"`
	Quantity   int     `json:"quantity"   binding:"required,min=1"`
	TotalPrice float64 `json:"total_price" binding:"required,gt=0"`
}

// ── JWT middleware ────────────────────────────────────────────
// Same JWT secret as user-service — tokens issued there are valid here.
func jwtMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" || len(authHeader) < 8 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing token"})
			return
		}
		tokenStr := authHeader[7:] // strip "Bearer "
		secret := os.Getenv("JWT_SECRET")
		token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method")
			}
			return []byte(secret), nil
		})
		if err != nil || !token.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			return
		}
		claims := token.Claims.(jwt.MapClaims)
		c.Set("userID", int(claims["sub"].(float64)))
		c.Next()
	}
}

// ── Handlers ──────────────────────────────────────────────────

func listOrders(c *gin.Context) {
	userID := c.GetInt("userID")
	rows, err := db.QueryContext(c.Request.Context(),
		`SELECT id, user_id, product_id, quantity, total_price, status, created_at, updated_at
		 FROM orders WHERE user_id = $1 ORDER BY created_at DESC`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	orders := []Order{}
	for rows.Next() {
		var o Order
		rows.Scan(&o.ID, &o.UserID, &o.ProductID, &o.Quantity, &o.TotalPrice, &o.Status, &o.CreatedAt, &o.UpdatedAt)
		orders = append(orders, o)
	}
	c.JSON(http.StatusOK, orders)
}

func createOrder(c *gin.Context) {
	userID := c.GetInt("userID")
	var req CreateOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var order Order
	err := db.QueryRowContext(c.Request.Context(),
		`INSERT INTO orders (user_id, product_id, quantity, total_price, status, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, 'pending', NOW(), NOW())
		 RETURNING id, user_id, product_id, quantity, total_price, status, created_at, updated_at`,
		userID, req.ProductID, req.Quantity, req.TotalPrice,
	).Scan(&order.ID, &order.UserID, &order.ProductID, &order.Quantity, &order.TotalPrice,
		&order.Status, &order.CreatedAt, &order.UpdatedAt)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// ── Publish to Redis (async notification) ─────────────────
	// notification-service subscribes to "order.created" and sends emails/webhooks.
	// We publish here AFTER the DB write succeeds — if Redis is down,
	// the order is still created (graceful degradation).
	go publishOrderCreated(order)

	c.JSON(http.StatusCreated, order)
}

func getOrder(c *gin.Context) {
	userID := c.GetInt("userID")
	orderID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid order ID"})
		return
	}

	var order Order
	err = db.QueryRowContext(c.Request.Context(),
		`SELECT id, user_id, product_id, quantity, total_price, status, created_at, updated_at
		 FROM orders WHERE id = $1 AND user_id = $2`, orderID, userID,
	).Scan(&order.ID, &order.UserID, &order.ProductID, &order.Quantity, &order.TotalPrice,
		&order.Status, &order.CreatedAt, &order.UpdatedAt)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "order not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, order)
}

// ── Redis Publisher ───────────────────────────────────────────
// Runs in a goroutine so it doesn't block the HTTP response.
func publishOrderCreated(order Order) {
	payload, _ := json.Marshal(map[string]interface{}{
		"event":    "order.created",
		"order_id": order.ID,
		"user_id":  order.UserID,
		"product_id": order.ProductID,
		"total_price": order.TotalPrice,
	})
	ctx := context.Background()
	if err := redisClient.Publish(ctx, "order.created", payload).Err(); err != nil {
		log.Printf("[redis] Failed to publish order.created: %v", err)
	} else {
		log.Printf("[redis] Published order.created for order %d", order.ID)
	}
}

// ── DB Init ───────────────────────────────────────────────────
func initDB() {
	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		getEnv("DB_HOST", "localhost"),
		getEnv("DB_PORT", "5432"),
		getEnv("DB_USER", "postgres"),
		getEnv("DB_PASSWORD", ""),
		getEnv("DB_NAME", "orders"),
	)

	var err error
	db, err = sql.Open("postgres", dsn)
	if err != nil {
		log.Fatalf("[db] Failed to open: %v", err)
	}
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err = db.Ping(); err != nil {
		log.Fatalf("[db] Cannot connect: %v", err)
	}

	// Create schema
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS orders (
			id          SERIAL PRIMARY KEY,
			user_id     INT NOT NULL,
			product_id  VARCHAR(50) NOT NULL,
			quantity    INT NOT NULL CHECK (quantity > 0),
			total_price DECIMAL(10,2) NOT NULL CHECK (total_price > 0),
			status      VARCHAR(20) NOT NULL DEFAULT 'pending',
			created_at  TIMESTAMPTZ DEFAULT NOW(),
			updated_at  TIMESTAMPTZ DEFAULT NOW()
		);
		CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);
	`)
	if err != nil {
		log.Fatalf("[db] Schema init failed: %v", err)
	}
	log.Println("[db] Schema initialised")
}

func initRedis() {
	redisClient = redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", getEnv("REDIS_HOST", "localhost"), getEnv("REDIS_PORT", "6379")),
		Password: getEnv("REDIS_PASSWORD", ""),
		DB:       0,
	})
	ctx := context.Background()
	if err := redisClient.Ping(ctx).Err(); err != nil {
		// Redis is optional — degraded mode logs a warning but doesn't exit
		log.Printf("[redis] Warning: cannot connect (%v). Order events will not be published.", err)
	} else {
		log.Println("[redis] Connected")
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// ── Main ──────────────────────────────────────────────────────
func main() {
	godotenv.Load() // load .env if present (dev only)
	prometheus.MustRegister(httpRequests)

	initDB()
	initRedis()

	if os.Getenv("GIN_MODE") == "" {
		gin.SetMode(gin.ReleaseMode) // suppress debug output in prod
	}

	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	// ── Health ────────────────────────────────────────────────
	r.GET("/health", func(c *gin.Context) {
		dbErr := db.PingContext(c.Request.Context())
		status := "ok"
		code := http.StatusOK
		if dbErr != nil {
			status = "error"
			code = http.StatusServiceUnavailable
		}
		c.JSON(code, gin.H{"status": status, "service": "order-service"})
	})

	// ── Metrics ───────────────────────────────────────────────
	// promhttp.Handler() returns a standard http.Handler wrapping the default registry
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// ── Orders (protected) ────────────────────────────────────
	orders := r.Group("/orders", jwtMiddleware())
	{
		orders.GET("", listOrders)
		orders.POST("", createOrder)
		orders.GET("/:id", getOrder)
	}

	port := getEnv("PORT", "8080")
	log.Printf("[order-service] Listening on :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("[order-service] Fatal: %v", err)
	}
}
