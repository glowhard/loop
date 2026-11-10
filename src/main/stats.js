// What the PC is doing right now, for the bar at the bottom of the window:
// processor, memory, graphics card, and how much of each is Loop itself.
const os = require('os');
const { spawn } = require('child_process');

let lastCpu = null;
let gpu = null; // { load, used, total } from the NVIDIA tool, when there is one
let gpuProc = null;

function cpuLoad() {
  let idle = 0;
  let total = 0;
  for (const c of os.cpus()) {
    for (const v of Object.values(c.times)) total += v;
    idle += c.times.idle;
  }
  const prev = lastCpu;
  lastCpu = { idle, total };
  if (!prev || total === prev.total) return 0;
  return Math.round(100 * (1 - (idle - prev.idle) / (total - prev.total)));
}

// One long-lived reader that prints a line every few seconds; far cheaper than
// starting a tool for every sample. PCs without an NVIDIA card just show no GPU figure.
function watchGpu() {
  if (gpuProc) return;
  try {
    gpuProc = spawn('nvidia-smi', ['--query-gpu=utilization.gpu,memory.used,memory.total', '--format=csv,noheader,nounits', '-l', '5'], {
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    return;
  }
  gpuProc.on('error', () => (gpu = null));
  gpuProc.on('exit', () => (gpu = null));
  gpuProc.stdout.on('data', (d) => {
    const line = String(d).trim().split(/\r?\n/).pop();
    const [load, used, total] = line.split(',').map((x) => Number(x));
    if (Number.isFinite(load)) gpu = { load, used, total };
  });
}

function stop() {
  if (gpuProc) gpuProc.kill();
  gpuProc = null;
}

// metrics: Electron's app.getAppMetrics()
function sample(metrics) {
  watchGpu();
  const total = os.totalmem();
  let appCpu = 0;
  let appMem = 0;
  for (const m of metrics || []) {
    appCpu += m.cpu.percentCPUUsage;
    appMem += m.memory.workingSetSize * 1024;
  }
  return {
    cpu: cpuLoad(),
    memUsed: total - os.freemem(),
    memTotal: total,
    gpu,
    appCpu: Math.round(appCpu / Math.max(1, os.cpus().length)), // share of the whole processor, like Task Manager
    appMem,
  };
}

module.exports = { sample, stop };
