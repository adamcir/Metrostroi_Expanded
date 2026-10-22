"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const net = require("node:net");
const {createBackend,normalizeRequest,safeDecision,envelope,parseModelDecision} = require("../mex_ai_server.js");
const sample = require("../example_request.json");
test("valid request and protocol version",()=>{
  assert.equal(normalizeRequest(sample).train.speed_kmh,60);
  assert.throws(()=>normalizeRequest({...sample,v:2}));
});
test("speed limit approach envelope",()=>{
  const input=normalizeRequest(sample);
  assert.ok(envelope(input).safeSpeed<80);
  assert.ok(envelope(input).safeSpeed>40);
  assert.ok(safeDecision(input,{mode:"ACCELERATE",target_speed_kmh:100,reason:"bad"}).target_speed_kmh<=envelope(input).safeSpeed);
});
test("route unknown must stop",()=>{
  const input=normalizeRequest({...sample,route:{known:false}});
  assert.equal(envelope(input).safeSpeed,0);
  assert.equal(safeDecision(input,{mode:"ACCELERATE",target_speed_kmh:90,reason:"bad"}).mode,"BRAKE");
});
test("invalid AI mode is rejected",()=>{
  assert.throws(()=>parseModelDecision('{"mode":"FLY","target_speed_kmh":60,"reason":"wrong"}'));
});
test("TCP NDJSON across fragmented packets",async()=>{
  const server=createBackend({host:"127.0.0.1",port:0,model:"mock",maxBytes:32768,timeoutMs:3000,maxActive:2},async()=>({mode:"BRAKE",target_speed_kmh:40,reason:"approaching limit"}));
  await new Promise((ok,bad)=>{server.once("error",bad);server.listen(0,"127.0.0.1",ok);});
  try {
    const response=await new Promise((ok,bad)=>{
      const client=net.connect(server.address().port,"127.0.0.1");
      let payload="";
      client.on("connect",()=>{let s=JSON.stringify(sample)+"\n";client.write(s.slice(0,10));client.write(s.slice(10));});
      client.on("data",chunk=>payload+=chunk.toString());
      client.on("error",bad);
      client.on("end",()=>{try{ok(JSON.parse(payload.trim()));}catch(e){bad(e);}});
    });
    assert.equal(response.id,"example1");
    assert.equal(response.type,"decision");
    assert.equal(response.status,"ok");
  } finally {await new Promise(ok=>server.close(ok));}
});
