"use strict";
const {test}=require("node:test");
const assert=require("node:assert/strict");
const net=require("node:net");
const {createBackend}=require("../mex_ai_server.js");
const sample=require("../example_request.json");
function send(port, request) {
  return new Promise((resolve, reject) => {
    const client=net.connect(port,"127.0.0.1");
    let received="";
    client.on("connect",()=>{
      const msg=JSON.stringify(request)+"\n";
      client.write(msg.slice(0,8));
      client.write(msg.slice(8));
    });
    client.on("data",buf=>received+=buf);
    client.on("error",reject);
    client.on("end",()=>{try{resolve(JSON.parse(received.trim()));}catch(e){reject(e);}});
  });
}
test("chat is read-only and uses separate model callback",async()=>{
  let drives=0, chats=0;
  const server=createBackend({host:"127.0.0.1",port:0,model:"mock",maxBytes:32768,timeoutMs:1200,maxActive:2},
    async ()=>{drives++;return {mode:"BRAKE",target_speed_kmh:0,reason:"stop"};},
    async input=>{chats++;return "Rozumim: "+input.message;});
  await new Promise((resolve,reject)=>{server.once("error",reject);server.listen(0,"127.0.0.1",resolve);});
  try {
    const reply=await send(server.address().port,{
      v:1,type:"chat",id:"hello123",text:"Kde je dalsi stanice?",
      train:{speed_kmh:0,ars_no_frequency:true},route:{known:false}
    });
    assert.equal(reply.type,"chat");
    assert.equal(reply.status,"ok");
    assert.match(reply.say,/Rozumim/);
    assert.equal(drives,0);
    assert.equal(chats,1);
    const rejected=await send(server.address().port,{v:1,type:"chat",id:"test2",text:""});
    assert.equal(rejected.type,"error");
  } finally {
    await new Promise(resolve=>server.close(resolve));
  }
});
