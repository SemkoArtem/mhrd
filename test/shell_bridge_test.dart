import 'package:flutter_test/flutter_test.dart';
import 'package:mhrd/models/connection.dart';
import 'package:mhrd/platform/linux_desktop.dart';
import 'package:mhrd/platform/shell_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // канал mhrd/shell реєструється при першому зверненні

  test('«Недавні» на значку: лише використані ПК, найновіший перший, не більше 8', () {
    final base = DateTime.utc(2026);
    Connection pc(int i, {bool used = true}) => Connection(
        id: 'pc$i', name: 'ПК $i', host: '10.0.0.$i', createdAt: base, updatedAt: base,
        lastUsed: used ? base.add(Duration(minutes: i)) : null);
    final all = [for (var i = 1; i <= 10; i++) pc(i), pc(11, used: false)];
    final r = ShellBridge.recent(all);
    expect(r.length, 8);
    expect(r.first.id, 'pc10');
    expect(r.map((c) => c.id), isNot(contains('pc11')));
  });

  test('--connect <id> з аргументів запуску → підключитись до цього ПК', () {
    ShellBridge.instance.handleArgs(['--connect', 'abc']);
    expect(ShellBridge.instance.pendingConnect.value, 'abc');
    ShellBridge.instance.pendingConnect.value = null;
    ShellBridge.instance.handleArgs(['--other']);
    expect(ShellBridge.instance.pendingConnect.value, isNull);
  });

  test('ярлик окремого акаунта: --connect <ПК>/<акаунт>', () {
    expect(ShellBridge.parseConnectTarget('pc-1'), ('pc-1', null));
    expect(ShellBridge.parseConnectTarget('pc-1/acc-2'), ('pc-1', 'acc-2'));
    expect(ShellBridge.parseConnectTarget('pc-1/'), ('pc-1', null));
  });

  test('ярлик Linux (.desktop): лапки, екранування, %, назва в один рядок', () {
    expect(LinuxDesktop.quoteExec(r'/opt/My Apps/mhrd'), r'"/opt/My Apps/mhrd"');
    expect(LinuxDesktop.quoteExec(r'a"b$c`d\e%f'), r'"a\"b\$c\`d\\e%%f"');
    final e = LinuxDesktop.entry(exe: '/home/u/MHRD.AppImage', target: 'pc-1/acc-2', name: 'Офіс\nсервер', icon: 'ua.mhrd.mhrd');
    expect(e, contains('Exec="/home/u/MHRD.AppImage" --connect "pc-1/acc-2"'));
    expect(e, contains('Name=Офіс сервер (MHRD)'));
    expect(e, contains('Icon=ua.mhrd.mhrd'));
    expect(e, startsWith('[Desktop Entry]\n'));
  });
}
