-- 终端 Neovim：从 Mapper 接口跳转到对应 XML 的 id="方法名"
local M = {}

--- 从当前行解析出方法名（简单匹配）
---@return string|nil
local function get_method_name_under_cursor()
	local line = vim.api.nvim_get_current_line()
	-- 匹配方法声明: 返回类型 方法名(
	local name = line:match("%s+([%w_]+)%s*%(")
	if name then
		local keywords = { "if", "for", "while", "switch", "catch", "return", "new", "class", "interface", "enum" }
		for _, kw in ipairs(keywords) do
			if name == kw then
				return nil
			end
		end
		return name
	end
	return nil
end

--- 根据 Mapper Java 路径推导 XML 路径
--- 例: .../operation-service/src/main/java/.../persistence/TransferDetailMapper.java
---  -> .../operation-service/src/main/resources/.../map/TransferDetailMapper.xml
---@param java_path string
---@return string|nil
local function java_path_to_xml_path(java_path)
	if not java_path:match("Mapper%.java$") then
		return nil
	end
	local xml = java_path:gsub("/src/main/java/", "/src/main/resources/"):gsub("%.java$", ".xml")
	-- 最后一级目录（persistence/config/...）统一为 map
	xml = xml:gsub("/([^/]+)/([^/]+%.xml)$", "/map/%2")
	return xml
end

--- 在文件内容中查找 id="methodName" 或 id='methodName' 的行号
---@param content string
---@param method_name string
---@return number|nil
local function find_id_line(content, method_name)
	local pattern = "id%s*=%s*[\"']" .. vim.pesc(method_name) .. "[\"']"
	for i, line in ipairs(vim.split(content, "\n")) do
		if line:match(pattern) then
			return i
		end
	end
	return nil
end

--- 在项目根下查找 Mapper.xml（可能在不同模块）
---@param root string
---@param mapper_basename string 如 TransferDetailMapper.xml
---@return string|nil
local function find_xml_in_project(root, mapper_basename)
	local cmd = string.format(
		"find %s -name %s -type f 2>/dev/null | head -1",
		vim.fn.shellescape(root),
		vim.fn.shellescape(mapper_basename)
	)
	local out = vim.fn.system(cmd)
	if out and out ~= "" then
		return vim.trim(out)
	end
	return nil
end

function M.jump_to_xml()
	local method = get_method_name_under_cursor()
	if not method then
		vim.notify("[mapper_jump] 光标不在方法名上", vim.log.levels.WARN)
		return
	end

	local buf_path = vim.api.nvim_buf_get_name(0)
	if not buf_path:match("Mapper%.java$") then
		vim.notify("[mapper_jump] 当前文件不是 Mapper 接口", vim.log.levels.WARN)
		return
	end

	local root = vim.fs.root(0, { ".git", "pom.xml", "mvnw" }) or vim.fn.getcwd()
	local mapper_basename = vim.fn.fnamemodify(buf_path, ":t"):gsub("%.java$", ".xml")

	-- 先按路径约定找
	local xml_path = java_path_to_xml_path(buf_path)
	if xml_path and vim.fn.filereadable(xml_path) == 1 then
		-- 找到 id=method 的行
		local content = table.concat(vim.fn.readfile(xml_path), "\n")
		local line = find_id_line(content, method)
		if line then
			vim.cmd("edit " .. vim.fn.fnameescape(xml_path))
			vim.api.nvim_win_set_cursor(0, { line, 0 })
			vim.cmd("normal! zz")
			return
		end
	end

	-- 否则在项目里按文件名找
	xml_path = find_xml_in_project(root, mapper_basename)
	if not xml_path or vim.fn.filereadable(xml_path) ~= 1 then
		vim.notify("[mapper_jump] 未找到 " .. mapper_basename, vim.log.levels.WARN)
		return
	end

	local content = table.concat(vim.fn.readfile(xml_path), "\n")
	local line = find_id_line(content, method)
	if not line then
		vim.notify('[mapper_jump] XML 中未找到 id="' .. method .. '"', vim.log.levels.WARN)
		return
	end

	vim.cmd("edit " .. vim.fn.fnameescape(xml_path))
	vim.api.nvim_win_set_cursor(0, { line, 0 })
	vim.cmd("normal! zz")
end

return M
