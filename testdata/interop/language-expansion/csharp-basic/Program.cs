interface IRunner
{
    void Run();
}

class Worker : IRunner
{
    public Worker()
    {
    }

    public void Run()
    {
        Helper();
    }

    private static void Helper()
    {
    }
}

static class Entry
{
    static void Boot()
    {
        var worker = new Worker();
        worker.Run();
    }
}
