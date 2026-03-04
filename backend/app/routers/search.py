from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import AuthenticatedUser, get_optional_user
from app.core.database import get_db
from app.schemas.schemas import UnifiedSearchOut
from app.services.search_service import UnifiedSearchService

router = APIRouter(prefix="/search", tags=["Search"])


@router.get("/unified", response_model=UnifiedSearchOut)
async def unified_search(
    q: str = Query(..., min_length=1, description="Arama metni"),
    city: Optional[str] = Query(None, description="Şehir filtresi"),
    offset: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    _user: Optional[AuthenticatedUser] = Depends(get_optional_user),
):
    service = UnifiedSearchService(db)
    return await service.search(query=q, city=city, offset=offset, limit=limit)
