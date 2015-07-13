--[[
Copyright (c) 2015 Calvin Rose

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

local lg = love.graphics

local EMPTY = {}

local function floor(x, y)
    return math.floor(x / y) * y
end

local function mod(x, y)
    return x - floor(x, y)
end

local function unpackCamera(t)
    local sx, sy, sw, sh
    if t.getWindow then -- assume t is a gamera camera
        sx, sy, sw, sh = t:getWindow()
    else
        sx, sy, sw, sh =
            t.sx or 0,
            t.sy or 0,
            t.sw or lg.getWidth(),
            t.sh or lg.getHeight()
    end
    return
        t.x or 0,
        t.y or 0,
        t.scale or t.zoom or 1,
        t.angle or t.rot or 0,
        sx, sy, sw, sh
end

local DEFAULT_COLOR = {220, 220, 220}
local DEFAULT_X_COLOR = {255, 0, 0}
local DEFAULT_Y_COLOR = {0, 255, 0}

local function unpackVisuals(t)
    local size = t.size or 256
    local sds = t.subdivisions or 4
    local color = t.color or DEFAULT_COLOR
    local drawScale
    if t.drawScale == nil then
        drawScale = true
    else
        drawScale = t.drawScale
    end
    local xColor = t.xColor or DEFAULT_X_COLOR
    local yColor = t.yColor or DEFAULT_Y_COLOR
    local fadeFactor = t.fadeFactor or 0.5
    return size, sds, drawScale, color, xColor, yColor, fadeFactor
end

local function getGridInterval(visuals, zoom)
    if visuals.interval then
        return visuals.interval
    else
        local size, sds = unpackVisuals(visuals)
        return size * math.pow(sds, -math.ceil(math.log(zoom, sds)))
    end
end

local function visible(camera)
    local camx, camy, zoom, angle, sx, sy, sw, sh = unpackCamera(camera)
    local w, h = sw / zoom, sh / zoom
    if angle ~= 0 then
        local sin, cos = math.abs(math.sin(angle)), math.abs(math.cos(angle))
        w, h = cos * w + sin * h, sin * w + cos * h
    end
    return camx - w * 0.5, camy - h * 0.5, w, h
end

local function toWorld(camera, screenx, screeny)
    local camx, camy, zoom, angle, sx, sy, sw, sh = unpackCamera(camera)
    local sin, cos = math.sin(angle), math.cos(angle)
    local x, y = (screenx - sw/2 - sx) / zoom, (screeny - sh/2 - sy) / zoom
    x, y = cos * x - sin * y, sin * x + cos * y
    return x + camx, y + camy
end

local function toScreen(camera, worldx, worldy)
    local camx, camy, zoom, angle, sx, sy, sw, sh = unpackCamera(camera)
    local sin, cos = math.sin(angle), math.cos(angle)
    local x, y = worldx - camx, worldy - camy
    x, y = cos * x + sin * y, -sin * x + cos * y
    return zoom * x + sw/2 + sx, zoom * y + sh/2 + sy
end

local function minorInterval(camera, visuals)
    local zoom = select(3, unpackCamera(camera))
    return getGridInterval(visuals, zoom)
end

local function majorInterval(camera, visuals)
    local sds = select(2, unpackVisuals(visuals))
    return sds * minorInterval(camera, visuals)
end

local function getCorners(camera)
    local sx, sy, sw, sh = select(5, unpackCamera(camera))
    local x1, y1 = toWorld(camera, sx, sy) -- top left
    local x2, y2 = toWorld(camera, sx + sw, sy) -- top right
    local x3, y3 = toWorld(camera, sx + sw, sy + sh) -- bottom right
    local x4, y4 = toWorld(camera, sx, sy + sh) -- bottom left
    return x1, y1, x2, y2, x3, y3, x4, y4
end

function intersect(x1, y1, x2, y2, x3, y3, x4, y4)
    local x21, x43 = x2 - x1, x4 - x3
    local y21, y43 = y2 - y1, y4 - y3
    local d = x21 * y43 - y21 * x43
    if d == 0 then return false end
    local xy34 = x3 * y4 - y3 * x4
    local xy12 = x1 * y2 - y1 * x2
    local a = xy34 * x21 - xy12 * x43
    local b = xy34 * y21 - xy12 * y43
    return a / d, b / d
end

local function drawLabel(camera, worldx, worly, label)
    lg.push()
    lg.origin()
    local x, y = toScreen(camera, worldx, worly)
    lg.printf(label, x + 2, y + 2, 400, "left")
    lg.pop()
end

local function draw(camera, visuals)
    camera = camera or EMPTY
    visuals = visuals or EMPTY
    local camx, camy, zoom, angle, sx, sy, sw, sh = unpackCamera(camera)
    local size, sds, ds, color, xColor, yColor, ff = unpackVisuals(visuals)
    local x1, y1, x2, y2, x3, y3, x4, y4 = getCorners(camera)
    local swapXYLabels = mod(angle + math.pi/4, math.pi) > math.pi/2

    lg.setScissor(sx, sy, sw, sh)
    local vx, vy, vw, vh = visible(camera)
    local d = getGridInterval(visuals, zoom)
    local delta = d / 2

    lg.push()
    lg.scale(zoom)
    lg.translate((sw / 2 + sx) / zoom, (sh / 2 + sy) / zoom)
    lg.rotate(-angle)
    lg.translate(-camx, -camy)

    local oldLineWidth = lg.getLineWidth()
    lg.setLineWidth(1 / zoom)

    -- lines parallel to y axis
    local xc = sds
    for x = floor(vx, d * sds), vx + vw, d do
        if math.abs(x) < delta then
            lg.setColor(yColor[1], yColor[2], yColor[3], 255)
            xc = 1
        elseif xc >= sds then
            lg.setColor(color[1], color[2], color[3], 255)
            xc = 1
        else
            lg.setColor(color[1] * ff, color[2] * ff, color[3] * ff, 255)
            xc = xc + 1
        end
        lg.line(x, vy, x, vy + vh)
        if ds then
            local cx, cy
            if swapXYLabels then
                cx, cy = x4, y4
            else
                cx, cy = x2, y2
            end
            local ix, iy = intersect(x1, y1, cx, cy, x, vy, x, vy + vh)
            if ix then
                drawLabel(camera, ix, iy, "x=" .. x)
            end
        end
    end

    -- lines parallel to x axis
    local yc = sds
    for y = floor(vy, d * sds), vy + vh, d do
        if math.abs(y) < delta then
            lg.setColor(xColor[1], xColor[2], xColor[3], 255)
            yc = 1
        elseif yc >= sds then
            lg.setColor(color[1], color[2], color[3], 255)
            yc = 1
        else
            lg.setColor(color[1] * ff, color[2] * ff, color[3] * ff, 255)
            yc = yc + 1
        end
        lg.line(vx, y, vx + vw, y)
        if ds then
            local cx, cy
            if swapXYLabels then
                cx, cy = x2, y2
            else
                cx, cy = x4, y4
            end
            local ix, iy = intersect(x1, y1, cx, cy, vx, y, vx + vw, y)
            if ix then
                drawLabel(camera, ix, iy, "y=" .. y)
            end
        end
    end

    lg.pop()
    lg.setLineWidth(1)

    -- draw origin
    lg.setColor(255, 255, 255, 255)
    local ox, oy = toScreen(camera, 0, 0)
    lg.rectangle("fill", ox - 1, oy - 1, 2, 2)
    lg.circle("line", ox, oy, 8)

    lg.setLineWidth(oldLineWidth)
    lg.setColor(255, 255, 255, 255)
    lg.setScissor()
end

local gridIndex = {
    toWorld = function (self, x, y) return toWorld(self.camera, x, y) end,
    toScreen = function (self, x, y) return toScreen(self.camera, x, y) end,
    draw = function (self) return draw(self.camera, self.visuals) end,
    minorInterval = function (self)
        return minorInterval(self.camera, self.visuals)
    end,
    majorInterval = function (self)
        return majorInterval(self.camera, self.visuals)
    end,
    visible = function (self) return visible(self.camera) end
}

local gridMt = {
    __index = gridIndex
}

local function grid(camera, visuals)
    return setmetatable({
        camera = camera or {},
        visuals = visuals or {}
    }, gridMt)
end

return {
    toWorld = toWorld,
    toScreen = toScreen,
    draw = draw,
    visible = visible,
    minorInterval = minorInterval,
    majorInterval = majorInterval,
    grid = grid
}
