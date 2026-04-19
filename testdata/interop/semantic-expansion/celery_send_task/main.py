import celery


@celery.task("users.refresh")
def refresh_users():
    return []


def enqueue_users():
    return celery.send_task("users.refresh")
