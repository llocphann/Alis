// Project requested cards into the finite Dashboard body, once per saved
// layout/viewport change. Pointer previews never re-pack neighbours.
function bounded(value, fallback, low, high) {
    return Number.isFinite(Number(value)) ? Math.max(low,Math.min(high,Number(value))) : fallback;
}
function overlaps(a,b,gap) {
    return a.x < b.x+b.width+gap-.001 && b.x < a.x+a.width+gap-.001
        && a.y < b.y+b.height+gap-.001 && b.y < a.y+a.height+gap-.001;
}
function freeRect(desired, minimum, width, height, obstacles, gap, shrink, plainSnapshot) {
    if (minimum.width > width || minimum.height > height) return null;
    var widths=shrink ? [desired.width,minimum.width] : [desired.width];
    var heights=shrink ? [desired.height,minimum.height] : [desired.height];
    var best=null, score=Infinity;
    var fastObstacles=plainSnapshot === true && typeof gap === "number";
    if (fastObstacles) {
        for (var oi=0;oi<obstacles.length;oi++) {
            var obstacle=obstacles[oi];
            if (!obstacle || typeof obstacle.x !== "number"
                    || typeof obstacle.y !== "number"
                    || typeof obstacle.width !== "number"
                    || typeof obstacle.height !== "number") {
                fastObstacles=false;
                break;
            }
        }
    }
    widths.forEach(function(w) { heights.forEach(function(h) {
        var xs=[desired.x,0,width-w], ys=[desired.y,0,height-h];
        obstacles.forEach(function(other) {
            xs.push(other.x-w-gap,other.x+other.width+gap);
            ys.push(other.y-h-gap,other.y+other.height+gap);
        });
        xs.forEach(function(x) {
            var xMatches=null;
            var fastX=fastObstacles && typeof w === "number"
                && typeof h === "number" && typeof x === "number";
            ys.forEach(function(y) {
                var r={x:x,y:y,width:w,height:h};
                if(x<0 || y<0 || x+w>width+.001 || y+h>height+.001) return;
                var blocked=false;
                if (fastX && typeof y === "number") {
                    if (xMatches === null) {
                        xMatches=[];
                        for (var xi=0;xi<obstacles.length;xi++) {
                            var xOther=obstacles[xi];
                            if (r.x < xOther.x+xOther.width+gap-.001
                                    && xOther.x < r.x+r.width+gap-.001)
                                xMatches.push(xi);
                        }
                    }
                    for (var yi=0;yi<xMatches.length;yi++) {
                        var yOther=obstacles[xMatches[yi]];
                        if (r.y < yOther.y+yOther.height+gap-.001
                                && yOther.y < r.y+r.height+gap-.001) {
                            blocked=true;
                            break;
                        }
                    }
                } else {
                    blocked=obstacles.some(function(other) { return overlaps(r,other,gap); });
                }
                if(blocked) return;
                // Prefer retaining size, then the nearest safe location.
                var cost=Math.pow(x-desired.x,2)+Math.pow(y-desired.y,2)
                    +4*(Math.pow(w-desired.width,2)+Math.pow(h-desired.height,2));
                if(cost<score) { best=r;score=cost; }
            });
        });
    }); });
    return best;
}
function project(entries, viewportWidth, viewportHeight, minimums, gap, reference) {
    // Old persisted scroll-workspace references must never enlarge this body.
    var width=Math.max(1,viewportWidth), height=Math.max(1,viewportHeight);
    var rects={}, obstacles=[], overflow=[];
    entries.filter(function(entry) { return entry.visible !== false; }).forEach(function(entry) {
        var min=minimums[entry.id] || {width:200,height:80};
        var w=Math.min(width,Math.max(min.width,bounded(entry.w,.3,.001,1)*width));
        var h=Math.min(height,Math.max(min.height,bounded(entry.h,.2,.001,1)*height));
        var desired={x:Math.min(width-w,bounded(entry.x,0,0,1)*width),
            y:Math.min(height-h,bounded(entry.y,0,0,1)*height),width:w,height:h};
        var best=freeRect(desired,min,width,height,obstacles,gap,true,true);
        if(!best) { overflow.push(entry.id);return; }
        rects[entry.id]=best;obstacles.push(best);
    });
    // The greedy solver preserves user positions whenever possible. On a
    // genuinely crowded/small viewport, never drop widgets: compute an
    // *in-memory* responsive grid instead of silently hiding overflow items.
    // Saved x/y/w/h remain untouched so the original arrangement comes back
    // automatically when the Dashboard has more space.
    if (overflow.length && entries.some(function(e) { return e.visible !== false; }))
        return responsiveGrid(entries,width,height,minimums,gap);
    return {width:width,height:height,rects:rects,overflow:overflow};
}
function responsiveGrid(entries, width, height, minimums, gap) {
    var shown=entries.filter(function(entry) { return entry.visible !== false; });
    var n=shown.length, rects={}, best=null;
    if (!n) return {width:width,height:height,rects:rects,overflow:[]};
    var requestedGap=Math.max(0,Number(gap)||0);
    for (var cols=1;cols<=n;cols++) {
        var rows=Math.ceil(n/cols), gapX=Math.min(requestedGap,width/Math.max(2,cols*3));
        var gapY=Math.min(requestedGap,height/Math.max(2,rows*3));
        var cellW=(width-(cols-1)*gapX)/cols;
        var cellH=(height-(rows-1)*gapY)/rows;
        if (cellW <= 0 || cellH <= 0) continue;
        var allowsMin=shown.every(function(e) {
            var min=minimums[e.id] || {width:1,height:1};
            return cellW+0.001 >= Math.min(width,Math.max(1,min.width))
                && cellH+0.001 >= Math.min(height,Math.max(1,min.height));
        });
        if (!allowsMin) continue;
        var ratio=cellW/cellH;
        // Prefer useful card aspect ratios without bias toward columns based
        // on widget identities. Responsive packing is deterministic.
        var score=Math.abs(Math.log(ratio/1.45)) + Math.abs(cols-rows)*0.025;
        if (!best || score<best.score) best={cols:cols,rows:rows,
            width:cellW,height:cellH,gapX:gapX,gapY:gapY,score:score};
    }
    if (!best) {
        // Extremely small windows still show the available modules; at this
        // point the safety hit-target can only be relaxed visually.
        var cols=Math.max(1,Math.min(n,Math.round(Math.sqrt(n*width/Math.max(1,height)))));
        var rows=Math.ceil(n/cols), gapX=Math.min(requestedGap,width/Math.max(2,cols*3));
        var gapY=Math.min(requestedGap,height/Math.max(2,rows*3));
        best={cols:cols,rows:rows,
            width:Math.max(1,(width-(cols-1)*gapX)/cols),
            height:Math.max(1,(height-(rows-1)*gapY)/rows),
            gapX:gapX,gapY:gapY};
    }
    // Keep approximate reading order rather than arbitrarily rearranging
    // cards by service type. All sorting happens only in the fallback view.
    shown=shown.slice().sort(function(a,b) {
        var ay=bounded(a.y,0,0,1),by=bounded(b.y,0,0,1);
        return Math.abs(ay-by) > .06 ? ay-by
            : bounded(a.x,0,0,1)-bounded(b.x,0,0,1);
    });
    shown.forEach(function(entry,i) {
        var col=i%best.cols, row=Math.floor(i/best.cols);
        rects[entry.id]={x:col*(best.width+best.gapX),
            y:row*(best.height+best.gapY),
            width:best.width,height:best.height};
    });
    return {width:width,height:height,rects:rects,overflow:[]};
}
