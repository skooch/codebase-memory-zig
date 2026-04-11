pub trait Runner {
    fn run(&self) -> String;
}

pub fn decorate<T>(value: T) -> T {
    value
}

pub struct Config {
    pub mode: String,
}

pub struct Worker {
    pub config: Config,
}

impl Runner for Worker {
    fn run(&self) -> String {
        self.config.mode.clone()
    }
}

pub fn boot() -> String {
    let worker = decorate(Worker {
        config: Config {
            mode: "batch".to_string(),
        },
    });
    worker.run()
}
