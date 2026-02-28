# ============================================
# app/models.py — Pydantic Models
# ============================================
# Pydantic models serve two purposes in FastAPI:
#   1. Request validation (FastAPI auto-parses and validates JSON body)
#   2. Response serialisation (only expose safe fields)
#
# MongoDB documents don't have a fixed schema, but we enforce one at
# the application layer for safety and documentation.

from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from bson import ObjectId


# Helper: make ObjectId JSON-serialisable
class PyObjectId(str):
    @classmethod
    def __get_validators__(cls):
        yield cls.validate

    @classmethod
    def validate(cls, v):
        if not ObjectId.is_valid(v):
            raise ValueError("Invalid ObjectId")
        return str(v)


# ── Request Models ─────────────────────────────────────────────
class ProductCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    description: str = Field(..., min_length=1)
    price: float = Field(..., gt=0, description="Price must be positive")
    stock: int = Field(..., ge=0, description="Stock quantity (>= 0)")
    category: str = Field(..., min_length=1)
    image_url: Optional[str] = None


class ProductUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = None
    price: Optional[float] = Field(None, gt=0)
    stock: Optional[int] = Field(None, ge=0)
    category: Optional[str] = None
    image_url: Optional[str] = None


# ── Response Models ────────────────────────────────────────────
class ProductResponse(BaseModel):
    id: str
    name: str
    description: str
    price: float
    stock: int
    category: str
    image_url: Optional[str]
    created_at: datetime
    updated_at: Optional[datetime]

    class Config:
        # Allow id field to come from _id in MongoDB document
        populate_by_name = True
