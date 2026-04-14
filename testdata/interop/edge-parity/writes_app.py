class Config:
    def __init__(self):
        self.name = "default"

def build_config():
    return Config()

current_config = build_config()

def update_config():
    current_config = build_config()
    return current_config
