import 'dart:io';

import 'package:logger/logger.dart';

/// One process in our tree.
class ProcessFootprint {
  const ProcessFootprint({
    required this.pid,
    required this.name,
    required this.bytes,
  });

  final int pid;

  /// `comm` from /proc — e.g. `WebKitWebProcess`, `WebKitNetworkProcess`.
  final String name;

  /// RSS. This is the figure WebKit's own MemoryPressureHandler compares
  /// against its kill threshold, so it is the right one for predicting a
  /// web-process kill.
  final int bytes;

  double get mb => bytes / (1024 * 1024);

  bool get isWebProcess => name.contains('WebProcess');
}

/// A reading of what this app costs the machine.
///
/// IMPORTANT — how to read [totalBytes] vs [largest]:
///
/// WebKit's kill threshold is PER PROCESS. "Unable to shrink memory
/// footprint of process (628 MB) below the kill thresold (600 MB)" is one
/// WebKitWebProcess exceeding its own limit, not the app exceeding a total.
/// So [largest] is what predicts a kill; [totalBytes] only describes the
/// load on the machine, and even then it over-counts, because summing RSS
/// counts memory shared between WebKit processes once per process. PSS is
/// used instead wherever `/proc/pid/smaps_rollup` is readable
/// ([usesProportionalSetSize]).
class MemorySnapshot {
  const MemorySnapshot({
    required this.totalBytes,
    required this.mainBytes,
    required this.processes,
    required this.isTreeAware,
    required this.usesProportionalSetSize,
    this.systemAvailableRatio,
  });

  final int totalBytes;
  final int mainBytes;

  /// Every descendant we could see, largest first. Excludes the main process.
  final List<ProcessFootprint> processes;

  final bool isTreeAware;
  final bool usesProportionalSetSize;

  /// MemAvailable / MemTotal, or null where /proc/meminfo isn't readable.
  /// This is the only honest "are we actually in trouble" signal.
  final double? systemAvailableRatio;

  ProcessFootprint? get largest => processes.isEmpty ? null : processes.first;

  ProcessFootprint? get largestWebProcess {
    for (final p in processes) {
      if (p.isWebProcess) return p;
    }
    return null;
  }

  int get childBytes => totalBytes - mainBytes;

  double get totalMb => totalBytes / (1024 * 1024);

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write('${totalMb.toStringAsFixed(1)} MB ')
      ..write(usesProportionalSetSize ? 'PSS' : 'RSS-sum')
      ..write(
        ' (main ${(mainBytes / (1024 * 1024)).toStringAsFixed(1)} MB + '
        '${processes.length} child)',
      );
    final biggest = largest;
    if (biggest != null) {
      buffer.write(
        ', biggest ${biggest.name}:${biggest.pid} '
        '${biggest.mb.toStringAsFixed(1)} MB',
      );
    }
    final ratio = systemAvailableRatio;
    if (ratio != null) {
      buffer.write(', system free ${(ratio * 100).toStringAsFixed(0)}%');
    }
    if (!isTreeAware) buffer.write(', TREE-BLIND');
    return buffer.toString();
  }
}

class MemoryGovernor {
  MemoryGovernor();

  static final Logger _logger = Logger(printer: SimplePrinter());

  /// Resolved by cross-checking `/proc/self/status` VmRSS against
  /// `/proc/self/statm`, so this stays correct on arm64 kernels built with
  /// 16K/64K pages rather than assuming 4096.
  static int? _pageSize;

  Future<MemorySnapshot?> snapshot() async {
    if (Platform.isLinux || Platform.isAndroid) {
      final linux = _linuxSnapshot();
      if (linux != null) return linux;
    }
    final own = _ownRss();
    if (own == null) return null;
    return MemorySnapshot(
      totalBytes: own,
      mainBytes: own,
      processes: const [],
      // Windows (msedgewebview2.exe) and macOS
      // (com.apple.WebKit.WebContent) also run web content out of process
      // and we have no cheap way to attribute those here.
      isTreeAware: false,
      usesProportionalSetSize: false,
    );
  }

  int? _ownRss() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return null;
    }
  }

  MemorySnapshot? _linuxSnapshot() {
    final self = pid;
    final usePss = _pssBytesOf(self) != null;
    final mine = (usePss ? _pssBytesOf(self) : null) ?? _rssBytesOf(self) ?? _ownRss();
    if (mine == null) return null;

    final children = <ProcessFootprint>[];
    var total = mine;
    for (final childPid in _descendantsOf(self)) {
      // Kill prediction needs RSS (what WebKit measures); machine load is
      // better described by PSS. Track both, report RSS per process.
      final rss = _rssBytesOf(childPid);
      if (rss == null) continue;
      children.add(
        ProcessFootprint(
          pid: childPid,
          name: _commOf(childPid) ?? 'pid $childPid',
          bytes: rss,
        ),
      );
      total += (usePss ? _pssBytesOf(childPid) : null) ?? rss;
    }
    children.sort((a, b) => b.bytes.compareTo(a.bytes));

    return MemorySnapshot(
      totalBytes: total,
      mainBytes: mine,
      processes: children,
      isTreeAware: true,
      usesProportionalSetSize: usePss,
      systemAvailableRatio: _systemAvailableRatio(),
    );
  }

  /// MemAvailable/MemTotal — the kernel's own estimate of how much can be
  /// handed out without swapping. Far more meaningful than any fixed MB
  /// budget the app could invent.
  double? _systemAvailableRatio() {
    try {
      int? total;
      int? available;
      for (final line in File('/proc/meminfo').readAsLinesSync()) {
        if (line.startsWith('MemTotal:')) {
          total = int.tryParse(line.replaceAll(RegExp(r'[^0-9]'), ''));
        } else if (line.startsWith('MemAvailable:')) {
          available = int.tryParse(line.replaceAll(RegExp(r'[^0-9]'), ''));
        }
        if (total != null && available != null) break;
      }
      if (total == null || available == null || total == 0) return null;
      return available / total;
    } catch (_) {
      return null;
    }
  }

  /// BFS over the `/proc` pid->ppid graph. WebKitWebProcess and
  /// WebKitNetworkProcess are forked by the UI process, so they appear as
  /// descendants.
  ///
  /// Android note: slot WebViews live in separate `android:process` app
  /// processes re-parented to the zygote, so they are not descendants of us
  /// and are not counted — they also have their own independent limits.
  Set<int> _descendantsOf(int root) {
    final childrenOf = <int, List<int>>{};
    try {
      for (final entry in Directory('/proc').listSync(followLinks: false)) {
        final childPid = int.tryParse(entry.path.split('/').last);
        if (childPid == null) continue;
        final parent = _ppidOf(childPid);
        if (parent == null) continue;
        childrenOf.putIfAbsent(parent, () => <int>[]).add(childPid);
      }
    } catch (_) {
      return const <int>{};
    }

    final found = <int>{};
    final queue = <int>[root];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final child in childrenOf[current] ?? const <int>[]) {
        if (found.add(child)) queue.add(child);
      }
    }
    return found;
  }

  String? _commOf(int target) {
    try {
      return File('/proc/$target/comm').readAsStringSync().trim();
    } catch (_) {
      return null;
    }
  }

  int? _ppidOf(int target) {
    try {
      final stat = File('/proc/$target/stat').readAsStringSync();
      // comm (field 2) is parenthesised and may itself contain spaces or
      // parens, so anchor on the LAST ')' rather than splitting naively.
      final close = stat.lastIndexOf(')');
      if (close == -1 || close + 2 >= stat.length) return null;
      final fields = stat.substring(close + 2).split(' ');
      if (fields.length < 2) return null;
      return int.tryParse(fields[1]);
    } catch (_) {
      return null;
    }
  }

  int? _rssBytesOf(int target) {
    try {
      final parts = File(
        '/proc/$target/statm',
      ).readAsStringSync().trim().split(RegExp(r'\s+'));
      if (parts.length < 2) return null;
      final pages = int.tryParse(parts[1]);
      if (pages == null) return null;
      return pages * _resolvePageSize();
    } catch (_) {
      return null;
    }
  }

  int? _pssBytesOf(int target) {
    try {
      for (final line in File(
        '/proc/$target/smaps_rollup',
      ).readAsLinesSync()) {
        if (!line.startsWith('Pss:')) continue;
        final kb = int.tryParse(line.replaceAll(RegExp(r'[^0-9]'), ''));
        if (kb == null) return null;
        return kb * 1024;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  int _resolvePageSize() {
    final cached = _pageSize;
    if (cached != null) return cached;
    var resolved = 4096;
    try {
      final parts = File(
        '/proc/self/statm',
      ).readAsStringSync().trim().split(RegExp(r'\s+'));
      final pages = int.tryParse(parts[1]) ?? 0;
      for (final line in File('/proc/self/status').readAsLinesSync()) {
        if (!line.startsWith('VmRSS:')) continue;
        final kb = int.tryParse(line.replaceAll(RegExp(r'[^0-9]'), ''));
        if (kb != null && pages > 0) {
          final derived = (kb * 1024) ~/ pages;
          if (derived >= 4096 && derived <= 65536) resolved = derived;
        }
        break;
      }
    } catch (_) {
      // keep 4096
    }
    _pageSize = resolved;
    return resolved;
  }

  void log(String label, MemorySnapshot snapshot) {
    _logger.d('[mem] $label: $snapshot');
  }
}