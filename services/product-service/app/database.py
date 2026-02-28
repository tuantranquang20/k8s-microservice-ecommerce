# ============================================
# app/database.py — Async MongoDB Connection
# ============================================
# Motor is PyMongo wrapped with asyncio support.
# WHY async: FastAPI is async-native. If we used synchronous PyMongo,
# database calls would block the event loop and kill throughput.

from motor.motor_asyncio import AsyncIOMotorClient
from pydantic_settings import BaseSettings
import os


class Settings(BaseSettings):
    MONGO_URI: str = "mongodb://localhost:27017"
    MONGO_DB: str  = "products"
    PORT: int      = 8000
    JWT_SECRET: str = "super-secret-change-in-prod"

    class Config:
        env_file = ".env"


settings = Settings()

# Global client — shared across all requests (connection pooling built in)
client: AsyncIOMotorClient = None


def get_database():
    """Return the products database handle."""
    return client[settings.MONGO_DB]


async def connect_to_mongo():
    """Called at app startup to initialise the Motor client."""
    global client
    client = AsyncIOMotorClient(settings.MONGO_URI)
    # Create text index for product search on first connection
    db = get_database()
    await db.products.create_index([("name", "text"), ("description", "text")])
    print(f"[db] Connected to MongoDB: {settings.MONGO_URI}/{settings.MONGO_DB}")


async def close_mongo_connection():
    """Called at app shutdown to release the connection pool."""
    global client
    if client:
        client.close()
        print("[db] MongoDB connection closed")
