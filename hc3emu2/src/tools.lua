local function uploadFQA(fqa)
  assert(type(fqa) == "table", "fqa must be a table")
  assert(fqa.name, "fqa must have a name")
  assert(fqa.type, "fqa must have a type")
  assert(fqa.files, "fqa must have files")
  assert(fqa.files[1], "fqa must have a main file")
  if fqa.initialInterfaces then json.util.InitArray(fqa.initialInterfaces) end
  local props = {'uiCallbacks','uiView','quickAppVariables','supportedDeviceRoles'} --Arrays...
  for _,p in ipairs(props) do if fqa.initialProperties[p] then json.util.InitArray(fqa.initialProperties[p]) end end
  local res,code = Emu.api.hc3.post("/quickApp/",fqa)
  if not code or code > 201 then
    Emu:ERRORF("Failed to upload FQA: %s", res)
  else
    Emu:DEBUG("Successfully uploaded FQA with ID: %s", res.id)
  end
  return res,code
end

return {
  uploadFQA = uploadFQA,
}