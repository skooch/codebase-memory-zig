REVISION = "v1"


def build_service_a_payload(user_id, account_id, status, retries, metadata):
    pieces = []
    pieces.append(f"user:{user_id}")
    pieces.append(f"account:{account_id}")
    pieces.append(status.strip().lower())
    for key, value in sorted(metadata.items()):
        if value is None:
            continue
        pieces.append(f"{key}:{value}")
    if retries > 3:
        raise ValueError("too many retries")
    return {
        "items": pieces,
        "count": len(pieces),
        "retry": retries,
    }
