'use strict';
// Existing fixed ffmpeg/TS recorder; --print-window adds only a persistent raw input adapter.
const fs = require('fs'), path = require('path'), { spawn } = require('child_process');
const readline = require('readline');
const args = process.argv.slice(2);
const val = (k, d) => { const i = args.indexOf(k); return i < 0 ? d : args[i + 1]; };
const printWindow = args.includes('--print-window'), synthetic = args.includes('--synthetic');
const seconds = Number(val('--seconds', 3600)), fps = Number(val('--fps', printWindow ? 8 : 20));
if (!(seconds >= 1 && seconds <= 10800 && Number.isInteger(fps) && fps >= 1 && fps <= 30)) throw Error('invalid bounded duration/fps');
if (printWindow && synthetic) throw Error('choose one input mode');
const title = val('--title', ''), targetPid = Number(val('--pid', 0)), hwnd = val('--hwnd', '');
if (!synthetic && !title) throw Error('exact window title required');
if (printWindow && (!Number.isSafeInteger(targetPid) || targetPid < 1 || !/^(0x[0-9a-f]+|[1-9][0-9]*)$/i.test(hwnd))) throw Error('--print-window requires explicit --pid, --hwnd and exact --title');
const root = path.resolve(val('--output-root', 'C:/rdd-footage'));
const run = path.join(root, 'continuous-' + new Date().toISOString().replace(/[:.]/g, '-') + '-' + process.pid);
const stopFile = path.resolve(val('--stop-file', path.join(run, 'STOP')));
if (fs.existsSync(stopFile)) throw Error('stop file already exists; choose a fresh path');
fs.mkdirSync(root, { recursive: true });
const free = fs.statfsSync(root), budget = Math.ceil(seconds * 550000 * 1.15) + 2147483648;
if (free.bavail * free.bsize < budget) throw Error('insufficient disk budget');
fs.mkdirSync(run);
const ffexe = 'D:/rdd/tools/ffmpeg/bin/ffmpeg.exe';
const meta = { startedUtc: new Date().toISOString(), mode: printWindow ? 'PrintWindow-flags2-rawBGRA' : synthetic ? 'synthetic' : 'gdigrab-legacy', title, targetPid: printWindow ? targetPid : undefined, hwnd: printWindow ? hwnd : undefined, synthetic, fpsRequested: fps, maxSeconds: seconds, stopFile, audio: 'none; no verified system loopback; never microphone', budgetBytes: budget };
const saveMeta = () => fs.writeFileSync(path.join(run, 'capture.json'), JSON.stringify(meta, null, 2));
saveMeta();
const ffd = fs.openSync(path.join(run, 'ffmpeg.log'), 'wx');
let child, producer, sent = false, ffResult, producerResult, final = false, pipeError;
const parts = () => fs.readdirSync(run).filter(n => n.endsWith('.ts')).map(name => ({ name, bytes: fs.statSync(path.join(run, name)).size }));
function requestStop(reason) {
  if (sent) return;
  sent = true; meta.stopRequestedUtc = new Date().toISOString(); meta.stopReason = reason;
  if (printWindow) {
    // Never send q into raw video. The producer sees this exact file and closes stdout.
    if (!fs.existsSync(stopFile)) fs.writeFileSync(stopFile, reason + '\n', { flag: 'wx' });
  } else if (child && !child.stdin.destroyed) { child.stdin.write('q\n'); child.stdin.end(); }
  saveMeta(); console.log(JSON.stringify({ event: printWindow ? 'producer-stop-requested' : 'graceful-q-sent', at: meta.stopRequestedUtc, reason }));
}
function finish() {
  if (final || !ffResult || (printWindow && !producerResult)) return;
  final = true; clearInterval(timer); fs.closeSync(ffd);
  let accounting;
  if (printWindow && fs.existsSync(path.join(run, 'producer-terminal.json'))) accounting = JSON.parse(fs.readFileSync(path.join(run, 'producer-terminal.json'), 'utf8'));
  const ok = ffResult.code === 0 && (!printWindow || (producerResult.code === 0 && accounting && accounting.ok)) && !pipeError && !meta.failure;
  const result = { ...meta, finishedUtc: new Date().toISOString(), code: ok ? 0 : 1, ffmpeg: ffResult, producer: producerResult, accounting, pipeError, stopSent: sent, parts: parts() };
  fs.writeFileSync(path.join(run, 'terminal.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify({ event: 'terminal', run, code: result.code, ffmpeg: ffResult, producer: producerResult, stopSent: sent }));
  process.exitCode = result.code;
}
function startEncoder(input) {
  const ffargs = ['-hide_banner', ...(printWindow ? ['-nostdin'] : []), ...input,
    ...(printWindow ? [] : ['-t', String(seconds)]), '-an', '-vf', 'pad=ceil(iw/2)*2:ceil(ih/2)*2',
    '-c:v', 'libx264', '-preset', 'veryfast', '-pix_fmt', 'yuv420p', '-b:v', '4M', '-maxrate', '4M', '-bufsize', '8M',
    '-g', String(fps * 2), '-sc_threshold', '0', '-f', 'segment', '-segment_time', String(synthetic ? 4 : 60),
    '-segment_list', path.join(run, 'segments.csv'), '-segment_list_type', 'csv', '-reset_timestamps', '1', path.join(run, 'part-%04d.ts')];
  meta.ffargs = ffargs; saveMeta();
  child = spawn(ffexe, ffargs, { stdio: ['pipe', 'ignore', ffd], windowsHide: true });
  meta.ffmpegPid = child.pid; saveMeta();
  child.stdin.on('error', e => {
    pipeError = e.message;
    if (printWindow) { requestStop('ffmpeg-input-error'); producer.stdout.unpipe(child.stdin); producer.stdout.resume(); }
  });
  child.on('error', e => { meta.spawnError = e.message; if (printWindow) { requestStop('ffmpeg-spawn-error'); producer.stdout.resume(); } });
  child.on('close', (code, signal) => {
    ffResult = { code, signal };
    if (printWindow && !producerResult) { requestStop('encoder-closed'); producer.stdout.unpipe(child.stdin); producer.stdout.resume(); }
    finish();
  });
  console.log(JSON.stringify({ event: 'started', run, pid: child.pid, producerPid: producer && producer.pid, stopFile, mode: meta.mode }));
}
const timer = setInterval(() => {
  if (!sent && fs.existsSync(stopFile)) requestStop('stop-file');
  if (printWindow && !sent) {
    try { const s = fs.statfsSync(root); if (s.bavail * s.bsize < 2147483648) { meta.failure = 'disk-reserve-below-2GiB'; requestStop(meta.failure); } }
    catch (e) { meta.failure = 'disk-check: ' + e.message; requestStop(meta.failure); }
  }
}, 250);
process.on('SIGINT', () => requestStop('SIGINT'));
process.on('SIGTERM', () => requestStop('SIGTERM'));
if (!printWindow) {
  startEncoder(synthetic ? ['-re', '-f', 'lavfi', '-i', 'testsrc2=size=1280x720:rate=' + fps] : ['-f', 'gdigrab', '-framerate', String(fps), '-draw_mouse', '0', '-i', 'title=' + title]);
} else {
  meta.timing = 'CFR held-previous-sample fill; no interpolation. frames.csv maps every media frame to actual capture UTC/monotonic time; repeated fill is not a fresh sample. Origin is first capture start; media duration rounds up to one frame.';
  const helper = path.join(__dirname, 'printwindow-producer.ps1');
  const producerArgs = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', helper, '-TargetPid', String(targetPid), '-HwndText', hwnd, '-ExactTitle', title, '-Fps', String(fps), '-Seconds', String(seconds), '-StopFile', stopFile, '-RunDir', run];
  meta.producerArgs = producerArgs; saveMeta();
  producer = spawn('powershell.exe', producerArgs, { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  meta.producerPid = producer.pid; saveMeta();
  const pd = fs.openSync(path.join(run, 'producer.log'), 'wx');
  const lines = readline.createInterface({ input: producer.stderr });
  lines.on('line', line => {
    fs.writeSync(pd, line + '\n');
    try {
      const event = JSON.parse(line);
      if (event.event === 'ready' && !child) {
        meta.source = event; saveMeta();
        startEncoder(['-f', 'rawvideo', '-pixel_format', 'bgra', '-video_size', event.width + 'x' + event.height, '-framerate', String(fps), '-i', 'pipe:0']);
        producer.stdout.pipe(child.stdin); // bounded Node/OS backpressure, no frame files
      }
    } catch (e) { if (line.startsWith('{')) { meta.protocolError = e.message; requestStop('producer-protocol-error'); } }
  });
  producer.on('error', e => { meta.producerSpawnError = e.message; });
  producer.on('close', (code, signal) => {
    fs.closeSync(pd); producerResult = { code, signal };
    if (!child) ffResult = { code: null, signal: null, notStarted: true };
    finish();
  });
}
