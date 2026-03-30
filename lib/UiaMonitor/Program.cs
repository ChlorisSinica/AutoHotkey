using System;
using System.Threading;
using System.Windows.Forms;

namespace UiaMonitor
{
    internal static class Program
    {
        private const string MutexName = "Global\\AhkUiaMonitor_Mutex";
        private const string MmfName = "AhkUiaState";

        [STAThread]
        static void Main(string[] args)
        {
            // ── 多重起動防止 ──
            using var mutex = new Mutex(true, MutexName, out bool created);
            if (!created)
            {
                // 既に起動中
                // --replace 引数付きなら既存プロセスを終了させて起き代わる
                if (args.Length > 0 && args[0] == "--replace")
                {
                    SharedState.SignalShutdown(MmfName);
                    Thread.Sleep(500);
                    if (!mutex.WaitOne(3000))
                    {
                        Console.Error.WriteLine("[UiaMonitor] 既存プロセスの終了を待てませんでした。");
                        return;
                    }
                }
                else
                {
                    Console.Error.WriteLine("[UiaMonitor] 既に起動中です。--replace で置き換え可能です。");
                    return;
                }
            }

            Console.WriteLine("[UiaMonitor] 起動中...");

            using var monitor = new MonitorService(MmfName);
            monitor.Start();

            Console.WriteLine("[UiaMonitor] 監視を開始しました。終了するにはウィンドウを閉じてください。");

            // WinForms メッセージループ（COM ディスパッチに必要）
            // 非表示フォームを使用
            var context = new ApplicationContext();

            // シャットダウンシグナル監視用タイマー
            var shutdownTimer = new System.Windows.Forms.Timer { Interval = 500 };
            shutdownTimer.Tick += (s, e) =>
            {
                if (monitor.IsShutdownRequested)
                {
                    shutdownTimer.Stop();
                    Application.ExitThread();
                }
            };
            shutdownTimer.Start();

            Application.Run(context);

            monitor.Stop();
            Console.WriteLine("[UiaMonitor] 終了しました。");
        }
    }
}
