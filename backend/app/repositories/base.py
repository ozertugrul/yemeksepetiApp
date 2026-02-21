"""
Repository base interface — database teknolojisinden bağımsız sözleşme.
Firestore → PostgreSQL geçişi bu arayüz üzerinden yönetilir.
"""
from abc import ABC, abstractmethod
from typing import List, Optional


class RestaurantRepositoryBase(ABC):
    @abstractmethod
    async def get_all_active(self, city: Optional[str] = None) -> list: ...

    @abstractmethod
    async def get_all(self) -> list: ...

    @abstractmethod
    async def get_by_id(self, restaurant_id: str) -> Optional[object]: ...

    @abstractmethod
    async def get_by_owner(self, owner_id: str) -> Optional[object]: ...

    @abstractmethod
    async def create(self, data: dict) -> object: ...

    @abstractmethod
    async def update(self, restaurant_id: str, data: dict) -> Optional[object]: ...

    @abstractmethod
    async def delete(self, restaurant_id: str) -> bool: ...


class MenuItemRepositoryBase(ABC):
    @abstractmethod
    async def get_by_restaurant(self, restaurant_id: str) -> list: ...

    @abstractmethod
    async def get_by_id(self, item_id: str) -> Optional[object]: ...

    @abstractmethod
    async def upsert(self, data: dict) -> object: ...

    @abstractmethod
    async def update_embedding(self, item_id: str, embedding: list) -> None: ...

    @abstractmethod
    async def find_similar(
        self, embedding: list, restaurant_id: Optional[str], top_k: int
    ) -> list: ...


class OrderRepositoryBase(ABC):
    @abstractmethod
    async def create(self, data: dict) -> object: ...

    @abstractmethod
    async def get_by_user(self, user_id: str) -> list: ...

    @abstractmethod
    async def get_by_restaurant(self, restaurant_id: str) -> list: ...

    @abstractmethod
    async def get_by_id(self, order_id: str) -> Optional[object]: ...

    @abstractmethod
    async def update_status(self, order_id: str, status: str) -> Optional[object]: ...


class UserRepositoryBase(ABC):
    @abstractmethod
    async def get_by_id(self, user_id: str) -> Optional[object]: ...

    @abstractmethod
    async def upsert(self, data: dict) -> object: ...

    @abstractmethod
    async def update(self, user_id: str, data: dict) -> Optional[object]: ...


class AddressRepositoryBase(ABC):
    @abstractmethod
    async def get_by_user(self, user_id: str) -> list: ...

    @abstractmethod
    async def create(self, data: dict) -> object: ...

    @abstractmethod
    async def update(self, address_id: str, data: dict) -> Optional[object]: ...

    @abstractmethod
    async def delete(self, address_id: str) -> bool: ...
