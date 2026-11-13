'use strict';
import * as fs from 'fs';
import { random, RUN, init, popen, read, write } from 'overwall.store';
const allowed = ['add', 'refresh', 'remove', 'settings', 'connect', 'disconnect', 'release', 'pair', 'pair_poll', 'logout'];
function valid(id) { return type(id) == 'string' && !!match(id, /^[A-Za-z0-9_-]{43}$/); }
function status() {
 let proc = popen(['/usr/bin/overwall', 'status']);
 let value = json(proc.read('all')); proc.close(); return value;
}
return { 'luci.overwall': {
 status: { args: {}, call: function() { return status(); } },
 command: { args: { action: '', data: '' }, call: function(request) {
  let action = request.args.action, data = request.args.data || '{}';
  if (index(allowed, action) < 0 || length(data) > 2200000) return { error: 'Invalid operation' };
  init();
  let previous = read('active-job', true);
  if (previous && !fs.stat(RUN + '/job-' + previous.id + '.result') && time() - previous.started_at < 190) return { error: 'Another operation is in progress. Please wait.' };
  // Keep a bounded ten-minute retry window, including lost HTTP responses.
  for (let file in fs.glob(RUN + '/job-*.result')) if (time() - fs.stat(file).mtime > 600) fs.unlink(file);
  let id = random(), path = RUN + '/job-' + id + '.input';
  let file = fs.open(path, 'w', 0600); if (!file) return { error: 'Cannot create request' };
  file.write(data); file.close(); write('active-job', { id, started_at: time() }, true);
  let proc = popen(['/usr/lib/overwall/job-start', action, path, id]); proc.read('all');
  if (proc.close() != 0) { fs.unlink(path); return { error: 'Cannot start operation' }; }
  return { job_id: id };
 } },
 job: { args: { id: '' }, call: function(request) {
  if (!valid(request.args.id)) return { error: 'Invalid job' };
  let raw = fs.readfile(RUN + '/job-' + request.args.id + '.result');
  if (!raw) return { done: false };
  try { return { done: true, result: json(raw) }; } catch (_) { return { error: 'Operation failed' }; }
 } }
} };
