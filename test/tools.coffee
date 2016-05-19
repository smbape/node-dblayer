fs = require 'fs'
sysPath = require 'path'
mkdirp = require 'mkdirp'
cp = require 'child_process'
spawn = cp.spawn
_ = require 'lodash'
ext = if process.platform.substring(0, 3) is 'win' then '.bat' else '.sh'

# @params:
#   filename: <String> filename without extension
#   variables: <Hash> Environmental variables to set
#   content: <String> Script content
#   done: <Function> Function to call on complete
# @usage:
#   createScript(String filename)
#   createScript(String filename, Hash variables)
#   createScript(String filename, String content)
#   createScript(String filename, Function done)
#   createScript(String filename, Hash variables, String content)
#   createScript(String filename, Hash variables, Function done)
#   createScript(String filename, String content, Function done)
#   createScript(String filename, Hash variables, String content, Function done)
exports.createScript = (filename, variables, content, done)->
    if arguments.length is 0
        return

    if arguments.length is 2
        if 'function' is typeof variables
            done = variables
        else if 'string' is typeof variables
            content = variables
    else if arguments.length is 3
        done = content if 'function' is typeof content
        content = variables if 'string' is typeof variables

    variables = {} if not _.isPlainObject variables
    content = '' if 'string' isnt typeof content

    script = []
    if ext is '.bat'
        script.push '@ECHO off\n@SETLOCAL'
        for variable, value of variables
            script.push "@SET #{variable}=#{value}"
    else
        script.push '#!/bin/sh\n'
        for variable, value of variables
            if 'string' is typeof value
                value = '"' + value.replace(/(["\\&|><;$])/g, '\\$1') + '"'
            script.push "export #{variable}=#{value}"

    script.push ''
    script.push content

    filename = filename + ext

    if 'function' is typeof done
        fs.writeFile filename, script.join('\n'), (err)->
            done err, filename
            return
        return

    fs.writeFileSync filename, script.join('\n')
    return filename

execute = (filename, args, stdio, done)->
    child = spawn filename, args, stdio: stdio
    child.on 'error', done
    child.on 'exit', ->
        done null, filename
        return
    return

# @params:
#   filename: <String> Filename
#   args: <Array> args to call Script with
#   stdio: <String|Array> ['inherit'|Array] stdio redirection
#   done: <Function> Function to call on complete
# @usage:
#   executeScript(String filename)
#   executeScript(String filename, Array args)
#   executeScript(String filename, Function done)
#   executeScript(String filename, Array args, Array stdio)
#   executeScript(String filename, Array args, Function done)
#   executeScript(String filename, Array args, String content, Function done)
exports.executeScript = (filename, args, stdio, done)->
    if arguments.length is 0
        return

    if arguments.length is 2
        done = args if 'function' is typeof args
    else if arguments.length is 3
        done = stdio if 'function' is typeof stdio

    args = [] if not Array.isArray args
    stdio = 'inherit' if 'inherit' isnt stdio and not Array.isArray stdio
    (done = ->) if 'function' isnt typeof done

    if ext is '.sh'
        child = spawn 'chmod', ['+x', filename], stdio: stdio
        child.on 'error', done
        child.on 'exit', ->
            execute filename, args, stdio, done
            return
        return

    execute filename, args, stdio, done
    return

exports.getScriptExtension = -> ext

temp = require 'temp'
rimraf = require 'rimraf'
tracked = {}
exports.getTemp = (tmp, track)->
    tmp = temp.mkdirSync('working') if not tmp
    tmp = sysPath.resolve tmp
    mkdirp.sync tmp
    if track and not tracked.hasOwnProperty tmp
        tracked[tmp] = true
        process.on 'exit', ->
            rimraf.sync tmp
            return

    tmp
