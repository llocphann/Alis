.pragma library

// Only add an effort field when the catalog identifies reasoning support.
// "off" keeps the provider default; GGUF separately supports true instant mode.
function supported(model) {
    if (!model || model.capabilities?.reasoning === "unsupported") return false
    const explicit = model.capabilities?.reasoning === "supported"
        || model.capabilities?.reasoningOff === "supported"
        || model.thinking === true
    const raw = (String(model.model ?? "") + " " + String(model.name ?? "") + " " + String(model.gguf_path ?? "")).toLowerCase()
    const inferred = /(?:qwen3|plusiq|defiant-fable|heretic|deepseek-r1|qwq|gpt-oss|thinking|reason|cogito|openthinker|sky-t1|exaone-deep|hunyuan-t1|marco-o1|glm-z1|kimi-k|phi-4-reasoning)/i.test(raw)
    if (!explicit && !inferred) return false
    return ["gguf", "openai", "openai-response", "gemini", "anthropic"].includes(model.api_format)
        && !(model.api_format === "gemini" && /image/i.test(model.model))
}

// An explicit text-session option. Preserve the user's model and provider;
// only canonical, positively verified local LM Studio URLs can opt into its
// stateless Responses transport. The Python transport re-verifies weights
// and the provider's explicit off switch before releasing each prompt.
function instantEndpoint(model) {
    if(model?.local!==true || model.local_verified!==true || model.provider_id!=="lmstudio"
            || model.capabilities?.reasoningOff!=="supported"
            || !["openai","openai-response"].includes(model.api_format)
            || !/^[0-9a-f]{64}$/.test(String(model.local_fingerprint ?? "")))return ""
    const endpoint=String(model.endpoint ?? "")
    const match=endpoint.match(/^https?:\/\/(?:127\.0\.0\.1|\[::1\])(?::([0-9]{1,5}))?\/v1\/(?:chat\/completions|responses)$/)
    if(!match || (match[1]!==undefined && (Number(match[1])<1 || Number(match[1])>65535)))return ""
    return endpoint.replace(/\/chat\/completions$/,"/responses")
}

function apply(model, input, effort) {
    if(effort==="instant" && model.api_format==="openai-response" && instantEndpoint(model))
        return Object.assign({},input,{reasoning:{effort:"none"},store:false,max_output_tokens:256})
    if (!supported(model) || !["low", "medium", "high", "xhigh", "max"].includes(effort)) return input
    const canonicalEffort = (effort === "xhigh" || effort === "max") ? "high" : effort
    const data = Object.assign({}, input)
    if (model.api_format === "openai") {
        data.reasoning_effort = canonicalEffort
        // Reasoning protocols may reject sampling controls. The provider's
        // explicit extraParams remain authoritative for sampling support.
        if (model.extraParams?.temperature === undefined) delete data.temperature
    } else if (model.api_format === "openai-response") {
        data.reasoning = Object.assign({}, data.reasoning ?? {}, {effort: canonicalEffort})
        if (model.extraParams?.temperature === undefined) delete data.temperature
    } else if (model.api_format === "gemini") {
        data.generationConfig = Object.assign({}, data.generationConfig ?? {})
        const thinking = Object.assign({}, data.generationConfig.thinkingConfig ?? {})
        if (/gemini-3/.test(model.model)) {
            delete thinking.thinkingBudget
            thinking.thinkingLevel = canonicalEffort
        } else if (/gemini-2\.5/.test(model.model)) {
            thinking.thinkingBudget = {low: 1024, medium: 4096, high: 8192, xhigh: 16384, max: 24576}[effort]
        } else return input
        data.generationConfig.thinkingConfig = thinking
    } else if (model.api_format === "anthropic") {
        if (/claude-(?:opus|sonnet)-(?:4-[6-9]|[5-9])/.test(model.model)) {
            data.thinking = {type: "adaptive"}
            data.output_config = Object.assign({}, data.output_config ?? {}, {effort: canonicalEffort})
            delete data.temperature
        } else {
            const budget = {low: 1024, medium: 4096, high: 8192, xhigh: 16384, max: 24576}[effort]
            data.thinking = {type: "enabled", budget_tokens: budget}
            data.max_tokens = Math.max(Number(data.max_tokens) || 4096, budget + 1024)
            data.temperature = 1
        }
    }
    return data
}
