"""
ChromaDB RAG module — initializes the vector database with knowledge docs.
Uses BAAI/bge-small-zh-v1.5 for Chinese-friendly embeddings (512 dims).
"""

import os

# 国内 HuggingFace 镜像
os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")

import chromadb
from chromadb.config import Settings
from sentence_transformers import SentenceTransformer
from config import CHROMA_DB_PATH, BGE_MODEL
from knowledge.projects import get_knowledge_docs

COLLECTION_NAME = "jfur_projects"

# Lazy-initialized globals
_embedding_model = None
_chroma_client = None
_collection = None


def get_embedding_model() -> SentenceTransformer:
    global _embedding_model
    if _embedding_model is None:
        _embedding_model = SentenceTransformer(BGE_MODEL)
    return _embedding_model


def get_chroma_collection():
    global _chroma_client, _collection
    if _collection is None:
        os.makedirs(CHROMA_DB_PATH, exist_ok=True)
        _chroma_client = chromadb.PersistentClient(path=CHROMA_DB_PATH)
        _collection = _chroma_client.get_or_create_collection(
            name=COLLECTION_NAME,
            metadata={"hnsw:space": "cosine"}
        )
    return _collection


def init_knowledge_base():
    """Index project knowledge into ChromaDB. Safe to call repeatedly (upserts)."""
    col = get_chroma_collection()
    model = get_embedding_model()
    docs = get_knowledge_docs()

    ids = []
    embeddings = []
    documents = []
    metadatas = []

    for i, doc in enumerate(docs):
        ids.append(f"proj_{i}")
        embeddings.append(model.encode(doc["text"]).tolist())
        documents.append(doc["text"])
        metadatas.append(doc["metadata"])

    col.upsert(ids=ids, embeddings=embeddings, documents=documents, metadatas=metadatas)
    return len(docs)


def search_similar(query: str, top_k: int = 2):
    """Vector similarity search — returns top_k matching projects."""
    col = get_chroma_collection()
    model = get_embedding_model()
    query_vec = model.encode(query).tolist()
    results = col.query(query_embeddings=[query_vec], n_results=top_k)
    if not results["metadatas"] or not results["metadatas"][0]:
        return []
    out = []
    for meta in results["metadatas"][0]:
        out.append(meta)
    return out
