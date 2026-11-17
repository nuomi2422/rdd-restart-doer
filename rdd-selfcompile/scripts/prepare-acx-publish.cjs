#!/usr/bin/env node
'use strict';
// Offline 174 representation helper. Never calls MCP or writes the AC library.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const PLANNER_NOTES = '174临时避险例外；原完整说明保留于FE1B源文件。顺序与守卫不变：就地挖三格→真实落底→等待四壁逐格补实完成并复核→就地封顶→纯后态取证。坐标材料以vars跨断点保存；in_place约束逐格生效，未知拒绝，材料不足不放置。正式拍摄结束后删除或规范化。';
const SOURCE_SHA256 = 'FE1BDD749F53EA928607C41F0C391200479948EE8718084D8EC19E27C6B08407';
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex').toUpperCase();
const deepSteps = steps => steps.flatMap(step => [step, ...deepSteps(step.children || [])]);
// JsonElement.toString writes these separators escaped; ordinary HTML characters are not escaped.
const serialize = value => JSON.stringify(value).split(String.fromCharCode(8232)).join(String.fromCharCode(92) + 'u2028')
    .split(String.fromCharCode(8233)).join(String.fromCharCode(92) + 'u2029');
function prepare(sourceBytes, companion, note = '') {
    assert.equal(sha256(sourceBytes), SOURCE_SHA256, 'only the accepted FE1B source is supported');
    assert.match(companion || '', /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
        'explicit companion UUID required; resolve current identity before publication');
    assert.equal(typeof note, 'string');
    const original = JSON.parse(sourceBytes.toString('utf8'));
    assert.equal(original.name, 'dig3_seal1_emergency');
    assert.equal(original.steps.length, 57);
    assert.equal(deepSteps(original.steps).length, 65);
    const transport = structuredClone(original);
    transport.planner_notes = PLANNER_NOTES;
    const restored = structuredClone(transport);
    restored.planner_notes = original.planner_notes;
    assert.deepEqual(restored, original, 'only planner_notes may differ');
    const acJson = JSON.stringify(transport);
    const args = { ac_json: acJson, note, companion };
    const payload = JSON.stringify(args);
    // MCP removes companion before constructing ExecuteToolPayload.argumentsJson.
    const nativeArguments = serialize({ ac_json: acJson, note });
    assert(nativeArguments.length <= 16384, 'native arguments exceed 16384 UTF-16 characters');
    assert(Buffer.byteLength(nativeArguments, 'utf8') <= 49152, 'UTF-8 encoding exceeds 3 * 16384');
    const received = JSON.parse(JSON.parse(nativeArguments).ac_json);
    received.planner_notes = original.planner_notes;
    assert.deepEqual(received, original, 'wire JSON roundtrip changed executable content');
    return { payload, proof: {
        scope: 'Offline representation proof only; no Java/native publication/Loader/Runner/world verification',
        sourceSha256: sha256(sourceBytes), transportAcJsonSha256: sha256(acJson),
        transportPayloadSha256: sha256(payload), nativeArgumentsSha256: sha256(nativeArguments),
        changedAstFields: ['planner_notes'], wholeAstEqual: false,
        allOtherAstFieldsEqual: true, topSteps: 57, deepSteps: 65,
        originalPlannerNotesSha256: sha256(original.planner_notes),
        transportPlannerNotesSha256: sha256(PLANNER_NOTES),
        cliArgumentsUtf16Chars: payload.length, cliArgumentsUtf8Bytes: Buffer.byteLength(payload),
        nativeArgumentsUtf16Chars: nativeArguments.length, nativeArgumentsUtf8Bytes: Buffer.byteLength(nativeArguments),
        limitUtf16Chars: 16384, headroomChars: 16384 - nativeArguments.length,
        originalMinifiedNativeChars: serialize({ ac_json: JSON.stringify(original), note }).length,
    } };
}
function main(argv) {
    if (argv.length === 1 && argv[0] === '--help') {
        console.log('Offline only: node prepare-acx-publish.cjs --source <FE1B.ac> --companion <UUID> --out-dir <new-dir> [--note-file <UTF8.txt>]');
        return;
    }
    const options = {};
    for (let i = 0; i < argv.length; i += 2) {
        assert(['--source', '--companion', '--out-dir', '--note-file'].includes(argv[i]), 'unknown option');
        assert(argv[i + 1] && !Object.hasOwn(options, argv[i]), 'missing or duplicate option');
        options[argv[i]] = argv[i + 1];
    }
    assert(options['--source'] && options['--companion'] && options['--out-dir'], 'source, companion, out-dir required');
    const sourcePath = path.resolve(options['--source']);
    const sourceBytes = fs.readFileSync(sourcePath);
    const note = options['--note-file'] ? fs.readFileSync(options['--note-file'], 'utf8') : '';
    const result = prepare(sourceBytes, options['--companion'], note);
    const output = path.resolve(options['--out-dir']);
    assert(output !== path.dirname(sourcePath), 'do not write transport files into the source directory');
    // No overwrite: all validation precedes exclusive directory creation.
    fs.mkdirSync(output);
    fs.writeFileSync(path.join(output, 'publish.json'), result.payload, { flag: 'wx' });
    fs.writeFileSync(path.join(output, 'proof.json'), JSON.stringify(result.proof, null, 2), { flag: 'wx' });
    assert.equal(sha256(fs.readFileSync(sourcePath)), SOURCE_SHA256, 'source changed during generation');
    console.log(JSON.stringify({ output, ...result.proof }, null, 2));
}
module.exports = { prepare, SOURCE_SHA256 };
if (require.main === module) {
    try { main(process.argv.slice(2)); }
    catch (error) { console.error('REFUSED: ' + error.message); process.exitCode = 1; }
}
