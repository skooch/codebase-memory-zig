package demo;

import java.util.List;

interface Runner {
    String run();
}

class Worker implements Runner {
    private final String mode;

    Worker(String mode) {
        this.mode = mode;
    }

    public String run() {
        return helper(mode);
    }

    static String helper(String mode) {
        return mode.toUpperCase();
    }
}

public class Main {
    static String boot() {
        Runner worker = new Worker("batch");
        return worker.run();
    }

    public static void main(String[] args) {
        System.out.println(boot());
    }
}
