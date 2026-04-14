class Config:
    def __init__(self):
        self.name = "default"

def update_config(cfg):
    cfg = Config()
    result = cfg.name
    return result
