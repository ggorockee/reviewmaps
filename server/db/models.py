from __future__ import annotations
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy import String, BigInteger, TIMESTAMP, Numeric, text, Text,ForeignKey, Integer

class Base(DeclarativeBase):
    pass

class Campaign(Base):
    __tablename__ = "campaign"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"), nullable=True)
    category: Mapped["Category"] = relationship(back_populates="campaigns")

    platform: Mapped[str] = mapped_column(String(20), nullable=False)
    company: Mapped[str] = mapped_column(String(255), nullable=False)
    company_link: Mapped[str | None] = mapped_column(Text)
    offer: Mapped[str] = mapped_column(Text)
    apply_deadline: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True))
    review_deadline: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True))
    address: Mapped[str | None] = mapped_column(Text)
    lat: Mapped[float | None] = mapped_column(Numeric(9, 6))
    lng: Mapped[float | None] = mapped_column(Numeric(9, 6))
    img_url: Mapped[str | None] = mapped_column(Text)
    search_text: Mapped[str | None] = mapped_column(String(20))
    created_at: Mapped[object] = mapped_column(TIMESTAMP(timezone=True), server_default=text("now()"))
    updated_at: Mapped[object] = mapped_column(TIMESTAMP(timezone=True), server_default=text("now()"))
    
    # --- 새로 추가된 컬럼들 ✨ ---
    source: Mapped[str | None] = mapped_column(String(100))
    title: Mapped[str | None] = mapped_column(Text)
    content_link: Mapped[str | None] = mapped_column(Text)
    campaign_type: Mapped[str | None] = mapped_column(String(50))
    region: Mapped[str | None] = mapped_column(String(100))
    campaign_channel: Mapped[str | None] = mapped_column(String(255)) # 여러 채널(,) 대비
    apply_from: Mapped[object | None] = mapped_column(TIMESTAMP(timezone=True))
    promotion_level: Mapped[int | None] = mapped_column(Integer, server_default=text("0"))

class Category(Base):
    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    created_at: Mapped[object] = mapped_column(TIMESTAMP(timezone=True), server_default=text("now()"))
    
    campaigns: Mapped[list["Campaign"]] = relationship(back_populates="category")
    display_order: Mapped[int] = mapped_column(Integer, server_default=text("99"), nullable=False)




class RawCategory(Base):
    __tablename__ = "raw_categories"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, index=True)
    raw_text: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    created_at: Mapped[object] = mapped_column(TIMESTAMP(timezone=True), server_default=text("now()"))

class CategoryMapping(Base):
    __tablename__ = "category_mappings"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, index=True)
    raw_category_id: Mapped[int] = mapped_column(ForeignKey("raw_categories.id"), nullable=False, unique=True)
    standard_category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"), nullable=False)