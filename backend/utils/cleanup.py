"""
图片清理工具
定时清理 uploads 目录下的过期文件
"""
import os
import time
import logging
from pathlib import Path
from datetime import datetime, timedelta
from typing import Optional

logger = logging.getLogger(__name__)


def cleanup_old_files(
    uploads_dir: str | Path,
    hours: int = 24,
    dry_run: bool = False
) -> dict:
    """
    清理指定时间前的文件

    Args:
        uploads_dir: 上传文件目录路径
        hours: 保留多少小时内的文件（默认24小时）
        dry_run: 试运行模式，只记录不删除

    Returns:
        清理结果统计
    """
    uploads_path = Path(uploads_dir)
    if not uploads_path.exists():
        logger.warning(f"目录不存在: {uploads_dir}")
        return {"deleted": 0, "skipped": 0, "errors": 0}

    cutoff_time = datetime.now() - timedelta(hours=hours)
    stats = {"deleted": 0, "skipped": 0, "errors": 0, "total": 0}

    for file_path in uploads_path.iterdir():
        if not file_path.is_file():
            continue

        stats["total"] += 1

        try:
            # 获取文件修改时间
            mtime = datetime.fromtimestamp(file_path.stat().st_mtime)

            if mtime < cutoff_time:
                if dry_run:
                    logger.info(f"[试运行] 会删除: {file_path.name} (最后修改: {mtime})")
                else:
                    file_path.unlink()
                    logger.info(f"已删除过期文件: {file_path.name} (最后修改: {mtime})")
                stats["deleted"] += 1
            else:
                stats["skipped"] += 1
        except Exception as e:
            logger.exception(f"处理文件失败: {file_path.name}")
            stats["errors"] += 1

    logger.info(
        f"清理完成 - 共扫描 {stats['total']} 个文件, "
        f"删除 {stats['deleted']} 个, "
        f"保留 {stats['skipped']} 个, "
        f"错误 {stats['errors']} 个"
    )
    return stats


async def periodic_cleanup_task(
    uploads_dir: str | Path,
    hours: int = 24,
    interval_seconds: int = 3600  # 每小时检查一次
):
    """
    定时清理任务

    Args:
        uploads_dir: 上传文件目录路径
        hours: 保留多少小时内的文件
        interval_seconds: 检查间隔（秒）
    """
    logger.info(f"定时清理任务已启动 - 每 {interval_seconds} 秒检查一次, 保留 {hours} 小时内的文件")

    while True:
        try:
            cleanup_old_files(uploads_dir, hours)
        except Exception as e:
            logger.exception("定时清理任务出错")

        await asyncio_sleep(interval_seconds)


# 兼容 asyncio.sleep 的导入
def asyncio_sleep(seconds: float):
    import asyncio
    return asyncio.sleep(seconds)
