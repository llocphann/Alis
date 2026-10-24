#!/usr/bin/env node
const fs = require('fs');
const vm = require('vm');
const assert = require('assert/strict');
const path = require('path');
const api = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../services/ai/AiReasoning.js'), 'utf8')
    .replace(/^\.pragma library\s*/, ''), api);
const model = (format, name = 'fixture') => ({api_format:format, model:name,
    capabilities:{reasoning:'supported'}, extraParams:{}});
const base = Object.freeze({temperature:.6, tools:[], messages:[]});
for (const effort of ['off','invalid',undefined])
    assert.equal(api.apply(model('openai'),base,effort),base, 'default does not alter provider data');
assert.equal(api.apply({...model('openai'),capabilities:{reasoning:'unknown'}},base,'high'),base);
assert.equal(api.apply(model('mistral'),base,'high'),base);
for (const effort of ['low','medium','high']) {
    const chat = api.apply(model('openai'),base,effort);
    assert.equal(chat.reasoning_effort,effort);
    assert.equal(chat.temperature,undefined);
    assert.equal(api.apply(model('openai-response'),base,effort).reasoning.effort,effort);
    const gemini3 = api.apply(model('gemini','gemini-3.1-pro'),base,effort);
    assert.equal(gemini3.generationConfig.thinkingConfig.thinkingLevel,effort);
    const gemini25 = api.apply(model('gemini','gemini-2.5-flash'),base,effort);
    assert.equal(gemini25.generationConfig.thinkingConfig.thinkingBudget,{low:1024,medium:4096,high:8192}[effort]);
    const adaptive = api.apply(model('anthropic','claude-sonnet-4-6'),base,effort);
    assert.equal(adaptive.thinking.type,'adaptive');
    assert.equal(adaptive.output_config.effort,effort);
    const manual = api.apply(model('anthropic','claude-sonnet-4-5'),base,effort);
    assert(manual.max_tokens > manual.thinking.budget_tokens);
    assert.equal(manual.temperature,1);
}
assert(!api.supported(model('gemini','gemini-3.1-flash-lite-image')));
assert(api.supported(model('gguf')));
assert.equal(api.apply({...model('openai'),extraParams:{temperature:1}},base,'high').temperature,.6);
assert.equal(base.temperature,.6, 'request overrides never mutate the input');
const local={...model('openai'),provider_id:'lmstudio',local:true,local_verified:true,
    local_fingerprint:'a'.repeat(64),endpoint:'http://127.0.0.1:1234/v1/chat/completions'};
assert.equal(api.instantEndpoint(local),'http://127.0.0.1:1234/v1/responses');
assert.equal(api.instantEndpoint({...local,endpoint:'http://[::1]:1234/v1/responses'}),'http://[::1]:1234/v1/responses');
for(const patch of [{local:false},{local_verified:false},{provider_id:'custom'},{local_fingerprint:''},
        {api_format:'gemini'},{endpoint:'https://remote.test/v1/chat/completions'},
        {endpoint:'http://127.0.0.1:0/v1/chat/completions'},
        {endpoint:'http://127.0.0.1:65536/v1/chat/completions'},
        {endpoint:'http://user@127.0.0.1/v1/chat/completions'},
        {endpoint:'http://127.0.0.1/v1/chat/completions?key=private'},
        {endpoint:'http://127.0.0.1/custom-route'}])assert.equal(api.instantEndpoint({...local,...patch}),'');
const instant=api.apply({...local,api_format:'openai-response'},base,'instant');
assert.equal(instant.reasoning.effort,'none');assert.equal(instant.store,false);
assert.equal(instant.max_output_tokens,256);assert.equal(base.reasoning,undefined);
assert.equal(api.apply(local,base,'off'),base,'explicit Instant must not change the provider-default option');
console.log('AI_REASONING_PASS defaults capabilities chat responses Gemini Claude immutability');
