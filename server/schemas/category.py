from __future__ import annotations
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional
from datetime import datetime

# --- Standard Category Schemas ---
class CategoryBase(BaseModel):
    name: str
    
class CategoryCreate(CategoryBase):
    pass

class Category(CategoryBase):
    id: int
    
    class Config:
        from_attributes = True # SQLAlchemy 모델을 Pydantic 모델로 자동 변환
        

# --- Raw Category Schemas ---
class RawCategory(BaseModel):
    id: int
    raw_text: str

    class Config:
        from_attributes = True
        
# --- Category Mapping Schemas ---
class CategoryMappingCreate(BaseModel):
    raw_category_id: int
    standard_category_id: int

class CategoryMapping(CategoryMappingCreate):
    id: int

    class Config:
        from_attributes = True