state = 0


def read_state():
    return state


def write_state():
    global state
    state = 1
    return state
