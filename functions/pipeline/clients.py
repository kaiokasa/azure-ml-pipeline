"""Lazily-created, reused SDK clients (one per worker process).

Azure  : identity-based (system-assigned managed identity), no key anywhere:
         STORAGE__blobServiceUri, STORAGE__queueServiceUri, COSMOS_ENDPOINT
Local  : STORAGE=UseDevelopmentStorage=true (Azurite); COSMOS_ENDPOINT unset -> Cosmos skipped.
"""

from __future__ import annotations

import os
from functools import lru_cache

import httpx


@lru_cache(maxsize=1)
def credential():
    from azure.identity import DefaultAzureCredential

    return DefaultAzureCredential()


@lru_cache(maxsize=1)
def blob_service():
    from azure.storage.blob import BlobServiceClient

    conn = os.getenv("STORAGE")
    if conn:
        return BlobServiceClient.from_connection_string(conn)
    return BlobServiceClient(account_url=os.environ["STORAGE__blobServiceUri"], credential=credential())


@lru_cache(maxsize=1)
def cosmos_container():
    endpoint = os.getenv("COSMOS_ENDPOINT")
    if not endpoint:
        return None
    from azure.cosmos import CosmosClient

    client = CosmosClient(endpoint, credential=credential())
    db = client.get_database_client(os.getenv("COSMOS_DATABASE", "pipeline"))
    return db.get_container_client(os.getenv("COSMOS_CONTAINER", "inferences"))


@lru_cache(maxsize=1)
def http_client() -> httpx.Client:
    # Reused connection pool. Generous read timeout: the API scales from 0 (cold start).
    timeout = httpx.Timeout(float(os.getenv("API_TIMEOUT_SECONDS", "45")), connect=10.0)
    return httpx.Client(base_url=os.environ["API_URL"], timeout=timeout)
