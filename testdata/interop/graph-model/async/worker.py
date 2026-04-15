import celery


def enqueue_users():
    return celery.delay("users.refresh")
