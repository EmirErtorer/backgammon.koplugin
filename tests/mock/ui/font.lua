local Font = {}
function Font:getFace(name, size) return { name = name, size = size or 20 } end
return Font
