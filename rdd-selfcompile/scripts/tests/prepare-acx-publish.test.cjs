'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { prepare, SOURCE_SHA256 } = require('../prepare-acx-publish.cjs');
const source = fs.readFileSync(path.resolve(__dirname, '../../../minecraft-numen/plugins/acx/scripts/stable/dig3_seal1_emergency.ac'));
const id = '00000000-0000-0000-0000-000000000001';
test('accepted source retains every AST field except explicit planner narrative', () => {
    const result = prepare(source, id, 'x'.repeat(21));
    const received = JSON.parse(JSON.parse(result.payload).ac_json);
    const original = JSON.parse(source);
    received.planner_notes = original.planner_notes;
    assert.deepEqual(received, original);
    assert.equal(result.proof.sourceSha256, SOURCE_SHA256);
    assert.equal(result.proof.nativeArgumentsUtf16Chars, 16229);
    assert.equal(result.proof.nativeArgumentsUtf8Bytes, 17373);
    assert.equal(result.proof.topSteps, 57);
    assert.equal(result.proof.deepSteps, 65);
});
test('oversized escaped note is refused, not trimmed', () => {
    assert.throws(() => prepare(source, id, '"'.repeat(1000)), /exceed/);
});
test('changed source is refused even if only whitespace changed', () => {
    assert.throws(() => prepare(Buffer.concat([source, Buffer.from(' ')]), id), /accepted FE1B/);
});
test('companion is mandatory with no historical default', () => {
    assert.throws(() => prepare(source, undefined), /UUID/);
    assert.throws(() => prepare(source, 'player'), /UUID/);
});
