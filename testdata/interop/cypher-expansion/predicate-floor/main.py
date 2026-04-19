mode = "prod"
count = 1


def bootstrap():
    return mode


def helper():
    return count


def trace():
    return helper()
