local RT = {}
function RT:renderUtf8Text(bb, x, baseline, face, text, kerning, bold, fgcolor)
    if type(text) ~= "string" then error("renderUtf8Text got a " .. type(text)) end
    if bb.addText then bb:addText(x, baseline, face.size, text, fgcolor) end
    return #text * math.floor(face.size * 0.5)
end
function RT:sizeUtf8Text(x, width, face, text)
    return { x = #tostring(text) * math.floor(face.size * 0.5) }
end
return RT
