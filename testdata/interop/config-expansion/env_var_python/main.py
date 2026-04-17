import os


def load_database_url():
    return os.getenv("DATABASE_URL")
