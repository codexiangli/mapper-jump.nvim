--- 终端 Neovim：从 Mapper 接口跳转到对应 XML 的 id="方法名"
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

--- 从当前行解析 id="methodName" 或 id='methodName'
---@return string|nil
local function get_id_under_cursor()
	local line = vim.api.nvim_get_current_line()
	local id = line:match("id%s*=%s*[\"']([%w_]+)[\"']")
	return id
end

--- 从 XML 内容中读取 mapper namespace（Mapper 接口全类名）
---@param content string
---@return string|nil
local function get_mapper_namespace(content)
	return content:match("<mapper%s+[^>]*namespace%s*=%s*[\"']([^\"']+)[\"']")
end

--- 根据 namespace 全类名在项目根下查找 Mapper.java
---@param root string
---@param namespace string 如 com.aihuishou.service.operation.persistence.TransferDetailMapper
---@return string|nil
local function find_java_by_namespace(root, namespace)
	local path_suffix = namespace:gsub("%.", "/") .. ".java"
	local cmd = string.format(
		"find %s -type f -path '*src/main/java/%s' 2>/dev/null | head -1",
		vim.fn.shellescape(root),
		vim.fn.shellescape(path_suffix)
	)
	local out = vim.fn.system(cmd)
	if out and out ~= "" then
		return vim.trim(out)
	end
	return nil
end

--- 在 Java 文件内容中查找方法声明的行号（方法名(）
---@param content string
---@param method_name string
---@return number|nil
local function find_method_line_in_java(content, method_name)
	local pattern = vim.pesc(method_name) .. "%s*%("
	for i, line in ipairs(vim.split(content, "\n")) do
		if line:match(pattern) then
			return i
		end
	end
	return nil
end

--- 根据 Mapper Java 路径推导 XML 路径
--- 例: .../operation-service/src/main/java/.../AaaMapper.java
---  -> .../operation-service/src/main/resources/AaaMapper.xml
---@param java_path string
---@return string|nil
local function java_path_to_xml_path(java_path)
	if not java_path:match("Mapper%.java$") then
		return nil
	end
	local xml = java_path:gsub("^(.*/src/main/)java/.*/([^/]+)%.java$", "%1resources/mapper/%2.xml")
	return xml
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

--- 从 Mapper.xml 跳转到对应 Mapper 接口的当前 id 方法（终端 Neovim 用，可绑到 gd）
function M.jump_to_java()
	local buf_path = vim.api.nvim_buf_get_name(0)
	if not buf_path:match("Mapper%.xml$") then
		vim.notify("[mapper_jump] 当前文件不是 Mapper XML", vim.log.levels.WARN)
		return
	end

	local method = get_id_under_cursor()
	if not method then
		vim.notify('[mapper_jump] 光标不在 id="方法名" 上', vim.log.levels.WARN)
		return
	end

	local content = table.concat(vim.fn.readfile(buf_path), "\n")
	local namespace = get_mapper_namespace(content)
	if not namespace then
		vim.notify('[mapper_jump] 未找到 <mapper namespace="...">', vim.log.levels.WARN)
		return
	end

	local root = vim.fs.root(0, { ".git", "pom.xml", "mvnw" }) or vim.fn.getcwd()
	local java_path = find_java_by_namespace(root, namespace)
	if not java_path or vim.fn.filereadable(java_path) ~= 1 then
		vim.notify("[mapper_jump] 未找到 " .. namespace, vim.log.levels.WARN)
		return
	end

	local java_content = table.concat(vim.fn.readfile(java_path), "\n")
	local line = find_method_line_in_java(java_content, method)
	if not line then
		vim.notify("[mapper_jump] 接口中未找到方法 " .. method, vim.log.levels.WARN)
		return
	end

	vim.cmd("edit " .. vim.fn.fnameescape(java_path))
	vim.api.nvim_win_set_cursor(0, { line, 0 })
	vim.cmd("normal! zz")
end

return M
