import httpx


@router.get("/api/users")
def users_endpoint():
    return []


def fetch_users():
    return httpx.get("/api/users")
