"""
API 调用重试工具
"""
import asyncio
import logging
from typing import Callable, TypeVar, Any
from functools import wraps

from config import API_RETRY_TIMES, API_RETRY_DELAY

logger = logging.getLogger(__name__)

T = TypeVar('T')


async def retry_async(
    func: Callable[..., T],
    *args: Any,
    retries: int = API_RETRY_TIMES,
    delay: float = API_RETRY_DELAY,
    **kwargs: Any
) -> T:
    """
    异步函数重试装饰器
    
    Args:
        func: 要执行的异步函数
        retries: 重试次数
        delay: 重试间隔（秒）
        *args: 函数位置参数
        **kwargs: 函数关键字参数
    
    Returns:
        函数执行结果
    
    Raises:
        Exception: 最后一次重试失败时抛出的异常
    """
    last_exception = None
    
    for attempt in range(retries + 1):
        try:
            return await func(*args, **kwargs)
        except Exception as e:
            last_exception = e
            if attempt < retries:
                logger.warning(
                    f"API 调用失败 (尝试 {attempt + 1}/{retries + 1}): {str(e)}"
                )
                logger.warning(f"将在 {delay} 秒后重试...")
                await asyncio.sleep(delay)
            else:
                logger.error(
                    f"API 调用失败，已达到最大重试次数 ({retries + 1} 次)"
                )
    
    raise last_exception
