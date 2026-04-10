pub const VERSION: u32 = 1;

pub struct Counter {
    pub value: i32,
}

pub trait Notifier {
    fn notify(&self, msg: &str);
}

impl Counter {
    pub fn new(value: i32) -> Self {
        Self { value }
    }

    pub fn bump(&mut self) {
        self.value += 1;
    }
}

impl Notifier for Counter {
    fn notify(&self, msg: &str) {
        println!("{msg}");
    }
}

pub fn emit(notifier: &impl Notifier, msg: &str) {
    notifier.notify(msg);
}

pub fn build(counter: &mut Counter) {
    counter.bump();
    emit(counter, "ready");
}
