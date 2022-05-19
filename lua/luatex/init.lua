local Job = require "plenary.job"

local M = {}

local config = {}

local defaultConfig = {
  previewer = "zathura",
  engine = "pdflatex",
  latexpath = "",
  cursorholdRecompile = false,
  useBiber = true,
  usingMacOS = false,
  usingSkim = false,
}

local function validateExecutable(name)
  return vim.fn.executable(name) == 1
end

local function getPath(str)
  -- return str:match("(.*" .. package.config:sub(1, 1) .. ")")
  return str:match("(.*)" .. package.config:sub(1, 1) .. ".*$")
end

local function getFile(str)
  return str:match("[^" .. package.config:sub(1, 1) .. "]+$") --[^/]+$
end

local function stripFileExtension(str)
  return str:match("(.*)%..*")
end

local function isTexFile(str)
  return str:match("[^.]+$") == "tex"
end

function fileExists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

local function copyFile(old_path, new_path)
  local old_file = io.open(old_path, "rb")
  local new_file = io.open(new_path, "wb")
  local old_file_sz, new_file_sz = 0, 0
  if not old_file or not new_file then
    return false
  end

  while true do
    local block = old_file:read(2^13)
    if not block then 
      old_file_sz = old_file:seek( "end" )
      break
    end
    new_file:write(block)
  end

  old_file:close()
  new_file_sz = new_file:seek( "end" )
  new_file:close()

  return new_file_sz == old_file_sz
end

local function preview()
  if (vim.b.luatexData.previewerRunning == 0 or config.usingMacOS) then
    vim.b.luatexData.previewerRunning = 1
    local job = Job:new(vim.b.luatexData.previewerCmd)
    job:sync()
  end
end

local function compileDone(job, returnValue)
  -- print(returnValue)
  -- print(vim.inspect(job:result()))
  if (fileExists(vim.b.luatexData.tmpdir .. package.config:sub(1, 1) .. vim.b.luatexData.tmpOutfile)) then
    vim.schedule(preview)
  else
    vim.schedule_wrap(function() vim.api.nvim_err_writeln("Luatex: Error creating output file!") end)    
  end
  -- print(vim.b.luatexData.tmpdir .. package.config:sub(1, 1) .. vim.b.luatexData.tmpOutfile)
end

local function compile()
  if (vim.b.luatexData ~= nil and vim.b.luatexData.previewRunning == 1) then
    local job = Job:new(vim.b.luatexData.runCmd)
    job:sync(10000)
  end
end

local function setupCommands()
  vim.api.nvim_create_user_command("LatexPreview", function()
    M.startPreview()
  end, {})

  vim.api.nvim_create_user_command("LatexSaveFile", function()
    M.createFinalPdf()
  end, {})
end

local function setupAutocommands()
  if config.cursorholdRecompile then
    vim.api.nvim_create_autocmd("CursorHold,CursorHoldI,BufWritePost", {
      pattern = "*",
      callback = function()
        vim.schedule(compile)
      end,
    })
  else
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = "*",
      callback = function()
        vim.schedule(compile)
      end,
    })
  end
end

local function prepareBufferVariables()
  -- Create temp directory for latex compilation files
  local tmpdir = vim.fn.tempname()
  local ok, error = pcall(vim.fn.mkdir, tmpdir, "p", "0700")
  if not ok then
    vim.api.nvim_err_writeln("Couldn't create temporary dir " .. tmpdir)
    return
  end

  local rootfile = vim.api.nvim_buf_get_name(0)
  local rootfilePath = getPath(rootfile)
  rootfile = getFile(rootfile)
  local tmpOutfile = stripFileExtension(rootfile) .. ".pdf"
  local finalPdf = rootfilePath .. package.config:sub(1, 1) .. stripFileExtension(rootfile) .. ".pdf"

  local runCmd = {
    command = config.engine,
    args = {
      '-shell-escape',
      '-interaction=nonstopmode',
      '-file-line-error',
      '-output-dir=' .. tmpdir,
      rootfile,
    },
    -- env = {
      -- 'TEXMFOUTPUT=' .. tmpdir,
      -- 'TEXINPUTS=' .. rootfilePath,
      -- 'TEXMFDIST=' .. config.latexpath,
    -- },
    on_exit = compileDone
  }

  local previewerCmd = {
    command = config.previewer,
    args = {
      tmpdir .. package.config:sub(1, 1) .. tmpOutfile,
    },
  }

  -- print(rootfile .. "\n".. rootfilePath .. "\n" .. tmpOutfile .. "\n" .. tmpdir)

  vim.b.luatexData = {
    previewRunning = 1,
    previewerRunning = 0,
    
    tmpdir = tmpdir,
    tmpOutfile = tmpOutfile,
    rootfile = rootfile,
    rootfilePath = rootfilePath,
    finalPdf = finalPdf,

    runCmd = runCmd,
    previewerCmd = previewerCmd,
  }
end

M.createFinalPdf = function()
  if vim.b.luatexData then
    local temp = vim.b.luatexData.tmpdir .. package.config:sub(1, 1) .. vim.b.luatexData.tmpOutfile
    if (fileExists(temp)) then
      copyFile(temp, vim.b.luatexData.finalPdf)
      print('Luatex: File "' .. vim.b.luatexData.finalPdf .. '" created!')
    end
  end
end

M.startPreview = function()
  if not isTexFile(vim.api.nvim_buf_get_name(0)) then
    vim.api.nvim_err_writeln("Luatex: File is not a latex file")
    return
  end

  if (vim.b.luatexData == nil) then
    prepareBufferVariables()
    setupAutocommands()

    -- print "Starting Tex preview"

    compile()

  end
end

M.setup = function(opts)
  config = vim.tbl_deep_extend("force", defaultConfig, opts or {})

  -- check engine and previewer
  if not validateExecutable(config.engine) then
    vim.api.nvim_err_writeln("'" .. config.engine .. "' not found or not an executable")
    return
  end

  if not validateExecutable(config.previewer) then
    vim.api.nvim_err_writeln("'" .. config.engine .. "' not found or not an executable")
    return
  end

  setupCommands()
end

return M
