// A damped spring string on one closed output perimeter, in logical pixels.
var presets = {
    calm:{amplitude:.035,propagation:.2,speed:.2,decay:.94,tension:.9,viscosity:.94,rebound:.08,corner:.25},
    balanced:{amplitude:.12,propagation:.35,speed:.3,decay:.85,tension:.8,viscosity:.85,rebound:.2,corner:.4},
    fluid:{amplitude:.32,propagation:.65,speed:.45,decay:.75,tension:.6,viscosity:.7,rebound:.35,corner:.65},
    deep:{amplitude:.65,propagation:1,speed:.3,decay:.78,tension:.4,viscosity:.65,rebound:.45,corner:.8}
};
// Named presets can be tuned without resetting existing custom wave controls.
var customDefaults = {amplitude:.8,propagation:.8,speed:.55,decay:.55,tension:.5,viscosity:.55,rebound:.6,corner:.8};
function bounded(value, fallback, maximum) {
    return Number.isFinite(Number(value)) ? Math.max(0,Math.min(maximum,Number(value))) : fallback;
}
function heightLimit(state) {
    return Math.min(4+32*state.parameters.amplitude, Math.min(state.width,state.height)*.3, 144);
}
function bodyStrength(options) {
    if (Number.isFinite(Number(options?.strength)) && Number(options.strength)>=0)
        return bounded(options.strength,1,4);
    // Preserve the strongest old presentation response until the shared control
    // is explicitly set. Old fields remain migration input, not active controls.
    return Math.max(.1,...["small","large","dock","notifications"].map(
        key=>bounded(options?.[key],1,4)));
}
function unit(value, fallback) {
    return Number.isFinite(Number(value)) ? Math.max(0,Math.min(1,Number(value))) : fallback;
}
function parameters(options) {
    var base = options?.preset === "custom" ? customDefaults : presets[options?.preset] || presets.balanced;
    var result = {};
    Object.keys(base).forEach(function(key) { result[key] = options?.preset === "custom" ? bounded(options[key],base[key],key === "amplitude" ? 4 : 1) : base[key]; });
    ["hover","press","open","close","drag"].forEach(function(key) { result[key] = unit(options?.[key],1); });
    result.idle = options?.idle === true;
    result.popupTravel = options?.popupTravel !== false;
    result.whitewater = unit(options?.whitewater,.65);
    result.strength = bodyStrength(options);
    return result;
}
function arc(edge, along, width, height) {
    if (edge === "right") return width+along;
    if (edge === "bottom") return width+height+width-along;
    if (edge === "left") return 2*width+height+height-along;
    return along;
}
function create(count, width, height, options) {
    var length=Math.max(1,2*(width+height)),corners=[0,width,width+height,2*width+height];
    return {count:count,width:width,height:height,length:length,
        displacement:Array(count).fill(0),velocity:Array(count).fill(0),mass:Array(count).fill(1),
        spectrumTargets:Array(count).fill(0),hasSpectrum:false,
        traveling:[],travelTargets:Array(count).fill(0),hasTravelTargets:false,
        // Geometry is immutable until this output resets. Corner classification
        // therefore belongs to initialization, not every solver substep.
        cornerSamples:Array.from({length:count},function(_,i) { return nearCorner(i*length/count,corners,length,length/count); }),
        acceleration:Array(count).fill(0),
        crestSource:Array(count).fill(0),crests:Array(count).fill(0),whitewater:Array(count).fill(0),crestPeak:0,
        parameters:options,mode:"SLEEPING",quiet:0,age:0,steps:0};
}
function circularDistance(a,b,length) {
    var distance=Math.abs(a-b)%length;
    return Math.min(distance,length-distance);
}
function nearCorner(location, corners, length, dx) {
    for(var i=0;i<corners.length;i++)
        if(circularDistance(location,corners[i],length)<dx*1.5) return true;
    return false;
}
function setMass(state, records) {
    state.mass.fill(1);
    records.forEach(function(record) {
        if (!record.mass || !record.progress) return;
        var center=arc(record.edge,record.along+record.span/2,state.width,state.height);
        var width=Math.max(40,record.span*.55);
        for(var i=0;i<state.count;i++) {
            var d=circularDistance(i*state.length/state.count,center,state.length)/width;
            state.mass[i]=Math.min(5,state.mass[i]+Math.min(4,record.mass)*record.progress*Math.exp(-d*d*2));
        }
    });
}
// Controller records are plain numeric geometry. Reuse only the expensive
// distance kernel; add each record's mass/progress in the original order and
// with the original double-precision operations. Keep the generic API above
// unchanged for callers with observable getters.
function setMassCached(state, records, cache) {
    var input=[state.count,state.length];
    records.forEach(function(record) {
        if (!record.mass || !record.progress) return;
        input.push(arc(record.edge,record.along+record.span/2,state.width,state.height),
            Math.max(40,record.span*.55),record.mass,record.progress);
    });
    var signature=input.join(":");
    if (cache.massSignature===signature && cache.massSnapshot) {
        // Restore rather than returning untouched: internal consumers may have
        // changed array contents since the last mass update.
        for (var i=0;i<state.count;i++) state.mass[i]=cache.massSnapshot[i];
        return;
    }
    state.mass.fill(1);
    var used = new Map();
    records.forEach(function(record) {
        if (!record.mass || !record.progress) return;
        var center = arc(record.edge,record.along+record.span/2,state.width,state.height);
        var width = Math.max(40,record.span*.55);
        var key = [state.count,state.length,center,width].join(":");
        var weights = cache.get(key);
        if (!weights) {
            weights = Array(state.count);
            for (var i=0;i<state.count;i++) {
                var d=circularDistance(i*state.length/state.count,center,state.length)/width;
                weights[i]=Math.exp(-d*d*2);
            }
        }
        used.set(key,weights);
        for (var i=0;i<state.count;i++)
            state.mass[i]=Math.min(5,state.mass[i]+Math.min(4,record.mass)*record.progress*weights[i]);
    });
    // No growing history: retain only kernels used by this geometry snapshot.
    cache.clear();
    used.forEach(function(weights,key) { cache.set(key,weights); });
    cache.massSignature=signature;
    cache.massSnapshot=state.mass.slice();
}
function impulse(state, edge, along, span, strength, mass) {
    var p=state.parameters;
    var center=arc(edge,along,state.width,state.height)%state.length;
    var width=Math.max(state.length/state.count*1.5,span*(.35+.3*p.propagation));
    var amount=strength*(60+280*p.amplitude)*Math.sqrt(Math.max(1,Math.min(6,mass || 1)));
    for(var i=0;i<state.count;i++) {
        var d=circularDistance(i*state.length/state.count,center,state.length)/width;
        state.velocity[i]=Math.max(-2000,Math.min(2000,state.velocity[i]+amount*Math.exp(-d*d*2)/Math.sqrt(state.mass[i])));
    }
    state.mode="ACTIVE";state.age=0;state.quiet=0;
}
// Two bounded moving excitations drive the same spring string. Their signed
// targets add, so concurrent/opening/closing waves can reinforce or cancel.
function travel(state, edge, along, span, strength, mass) {
    if (!state.parameters.popupTravel || !Number.isFinite(strength) || !strength
            || !Number.isFinite(along) || !Number.isFinite(span)) return false;
    var p=state.parameters,center=arc(edge,along,state.width,state.height);
    var width=Math.max(state.length/state.count*1.5,Math.min(state.width,state.height)*.04+span*.16);
    var amplitude=heightLimit(state)*Math.max(-4,Math.min(4,strength))*1.8*Math.sqrt(Math.max(1,Math.min(4,Number.isFinite(mass) ? mass : 1)));
    var distance=state.length/2*(.2+.8*p.propagation),speed=320+1280*p.speed;
    state.traveling=state.traveling.slice(-14).concat([-1,1].map(function(direction) {
        return {origin:center,center:center,direction:direction,traveled:0,distance:distance,speed:speed,width:width,amplitude:amplitude};
    }));
    state.mode="ACTIVE";state.age=0;state.quiet=0;
    return true;
}
function clearTravel(state) {
    state.traveling=[];state.travelTargets.fill(0);state.hasTravelTargets=false;
}
function travelEnvelope(traveled, distance) {
    if (!Number.isFinite(traveled) || !Number.isFinite(distance) || distance<=0) return 0;
    var fraction=Math.max(0,Math.min(1,traveled/distance)),remaining=1-fraction;
    return remaining*remaining*Math.exp(-fraction);
}
function advanceTravel(state, elapsed) {
    if(!state.traveling.length && !state.hasTravelTargets) return;
    state.travelTargets.fill(0);
    state.hasTravelTargets=false;
    var dx=state.length/state.count,p=state.parameters,kept=0;
    for(var packetIndex=0;packetIndex<state.traveling.length;packetIndex++) {
        var packet=state.traveling[packetIndex];
        packet.traveled+=packet.speed*elapsed;
        if(packet.traveled>=packet.distance) continue;
        state.traveling[kept++]=packet;state.hasTravelTargets=true;
        packet.center=((packet.origin+packet.direction*packet.traveled)%state.length+state.length)%state.length;
        var fade=travelEnvelope(packet.traveled,packet.distance);
        var center=Math.round(packet.center/dx),radius=Math.min(Math.ceil(packet.width*2.5/dx),Math.floor(state.count/4));
        // Evaluate only the compact packet's support, rather than every sample
        // for every popup. Scratch targets and acceleration arrays are reused.
        for(var offset=-radius;offset<=radius;offset++) {
            var i=(center+offset+state.count)%state.count;
            var d=((i*dx-packet.center+state.length*1.5)%state.length-state.length/2)/packet.width;
            var wake=d+packet.direction*1.45;
            var shape=Math.exp(-d*d*2)-.45*Math.exp(-wake*wake*2);
            var corner=state.cornerSamples[i];
            state.travelTargets[i]+=packet.amplitude*fade*shape*(corner ? .15+.85*p.corner : 1);
        }
    }
    state.traveling.length=kept;
}
// Present a bounded audio shape in the existing field. CAVA supplies the clock;
// this path never wakes or adds energy to the interaction spring solver.
function spectrum(state, edges, points, ceiling, strength, phase) {
    var count=points?.length || 0,changed=false,active=false;
    var maximum=Math.min(96,Math.min(state.width,state.height)*.12)*bounded(strength,0,4);
    var limit=Math.min(192,Math.min(state.width,state.height)*.18);
    state.spectrumLimit=count && maximum>0 ? limit : 0;
    var normalizer=Math.max(20,Number(ceiling) || 100);
    for(var i=0;i<state.count;i++) {
        var location=i*state.length/state.count,edge,along,length;
        if(location<state.width) { edge="top";along=location;length=state.width; }
        else if(location<state.width+state.height) { edge="right";along=location-state.width;length=state.height; }
        else if(location<2*state.width+state.height) { edge="bottom";along=2*state.width+state.height-location;length=state.width; }
        else { edge="left";along=state.length-location;length=state.height; }
        var t=along/Math.max(1,length),target=0;
        if(count && edges.indexOf(edge)>=0 && maximum>0) {
            var position=t*(count-1),low=Math.floor(position),high=Math.min(count-1,low+1);
            var a=Number(points[low]),b=Number(points[high]);
            var level=((Number.isFinite(a)?Math.max(0,a):0)*(1-(position-low))+(Number.isFinite(b)?Math.max(0,b):0)*(position-low))/normalizer;
            level=Math.sqrt(Math.max(0,Math.min(1,level)));
            // Old iNiR carrier: index*.5 + phase, driven at CAVA frame cadence.
            // Audio is a presentation shape, independent of the interaction
            // spring string. Peaks respond in this frame rather than seconds.
            if(level>.025) target=Math.min(limit,maximum*level)*Math.sin(position*.5+(Number(phase)||0))*Math.pow(Math.sin(t*Math.PI),2);
        }
        if(Math.abs(target-state.spectrumTargets[i])>.005 || (target===0 && state.spectrumTargets[i]!==0)) {
            changed=true;state.spectrumTargets[i]=target;
        }
        active=active || Math.abs(state.spectrumTargets[i])>.005;
    }
    state.hasSpectrum=active;
    return changed;
}
function advance(state, elapsed) {
    if(state.mode === "SLEEPING") return false;
    var p=state.parameters,dx=state.length/state.count;
    var speed=(160+700*p.speed)*(.3+.7*p.propagation);
    var parts=Math.ceil(Math.max(0,Math.min(.05,elapsed))*Math.max(120,2.5*speed/dx));
    var dt=Math.max(0,Math.min(.05,elapsed))/Math.max(1,parts);
    var limit=heightLimit(state);
    for(var step=0;step<parts;step++) {
        advanceTravel(state,dt);
        var acceleration=state.acceleration;
        for(var i=0;i<state.count;i++) {
            var left=(i+state.count-1)%state.count,right=(i+1)%state.count;
            var atCorner=state.cornerSamples[i];
            var transfer=atCorner ? .15+.85*p.corner : 1;
            var lap=state.displacement[left]+state.displacement[right]-2*state.displacement[i];
            var viscous=state.velocity[left]+state.velocity[right]-2*state.velocity[i];
            var spring=(18+62*p.tension)*(.4+.6*p.rebound);
            var damping=1.2+7*p.decay+3*(1-p.propagation)+(atCorner?(1-p.corner)*2:0);
            acceleration[i]=(speed*speed/(dx*dx)*lap*transfer+spring*(0-state.displacement[i])
                +(60+120*p.tension)*state.travelTargets[i]
                +p.viscosity*900/(dx*dx)*viscous)/state.mass[i]-damping*state.velocity[i];
        }
        for(var j=0;j<state.count;j++) {
            state.velocity[j]+=acceleration[j]*dt;
            state.displacement[j]+=state.velocity[j]*dt;
            if(Math.abs(state.displacement[j])>limit) {
                state.displacement[j]=Math.sign(state.displacement[j])*limit;
                state.velocity[j]*=.2;
            }
        }
        state.steps++;
    }
    state.age+=elapsed;
    var quiet=state.traveling.length===0 && state.displacement.every(function(v) { return Math.abs(v)<.025; })
        && state.velocity.every(function(v) { return Math.abs(v)<.12; });
    state.quiet=quiet ? state.quiet+1 : 0;
    if(state.quiet>=8) {
        state.displacement.fill(0);
        state.velocity.fill(0);state.mode="SLEEPING";
    } else state.mode=state.age<.2 ? "ACTIVE" : "SETTLING";
    return true;
}

// Presentation only: signed spring displacement remains untouched so opposite
// waves still cancel. A five-tap filter removes single-sample needles; the C1
// positive shoulder never erodes the resting Edge. Compact shoulders and a soft
// height limit make taller round crests without hard-clipped plateaus.
function smoothRange(low, high, value) {
    var t=Math.max(0,Math.min(1,(value-low)/(high-low)));
    return t*t*(3-2*t);
}
function projectCrests(state, foamAllowed) {
    var count=state.count,source=state.crestSource,crests=state.crests,peak=0;
    for(var i=0;i<count;i++) {
        var h=(state.displacement[(i+count-2)%count]+4*state.displacement[(i+count-1)%count]
            +6*state.displacement[i]+4*state.displacement[(i+1)%count]+state.displacement[(i+2)%count])/16;
        if(state.hasSpectrum)
            h+=(state.spectrumTargets[(i+count-2)%count]+4*state.spectrumTargets[(i+count-1)%count]
                +6*state.spectrumTargets[i]+4*state.spectrumTargets[(i+1)%count]+state.spectrumTargets[(i+2)%count])/16;
        h=Number.isFinite(h) ? Math.max(0,h) : 0;
        source[i]=h*h/(h+.5);
        peak=Math.max(peak,source[i]);
    }
    var limit=Math.max(state.spectrumLimit || 0,Math.min(192,heightLimit(state)*2,Math.min(state.width,state.height)*.35));
    state.crestPeak=0;
    for(var j=0;j<count;j++) {
        var relative=peak>0 ? source[j]/peak : 0;
        var shaped=source[j]*(.35+2.05*relative*relative);
        crests[j]=limit>0 ? limit*(1-Math.exp(-shaped/limit)) : 0;
        state.crestPeak=Math.max(state.crestPeak,crests[j]);
    }
    // Whitewater rides fast/steep crests in the existing texture's blue channel.
    // No particles, extra render target, independent clock or foam-only timer.
    var dx=state.length/count;
    for(var k=0;k<count;k++) {
        var left=crests[(k+count-1)%count],right=crests[(k+1)%count];
        var curvature=(2*crests[k]-left-right)/dx;
        var steepness=Math.abs(right-left)/(2*dx);
        state.whitewater[k]=foamAllowed ? state.parameters.whitewater
            *smoothRange(.05,.45,crests[k]/Math.max(1,limit))
            *smoothRange(.05,.28,Math.max(curvature,steepness*.35))
            *smoothRange(6,100,Math.abs(state.velocity[k])) : 0;
    }
    return state.crestPeak;
}
