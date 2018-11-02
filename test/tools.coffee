fs = require 'fs'
sysPath = require 'path'
{ spawn } = require 'child_process'
{ Writable } = require('stream')
mkdirp = require 'mkdirp'
isPlainObject = require 'lodash/isPlainObject'
ext = if process.platform is 'win32' then '.bat' else '.sh'
LF = if process.platform is 'win32' then '\r\n' else '\n'

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

    variables = {} if not isPlainObject variables
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
        fs.writeFile filename, script.join(LF) + LF, (err)->
            done err, filename
            return
        return

    fs.writeFileSync filename, script.join(LF) + LF
    return filename

execute = (filename, args, stdio, done)->
    outread = 0
    outbuffers = []
    outwrite
    errread = 0
    errbuffers = []
    errwrite

    # Buffer.concat(buffers, nread)
    [ stdin, stdout, stderr ] = if stdio is "inherit" then [0, 1, 2] else if Array.isArray(stdio) then stdio else []

    if not stdout
        stdout = "pipe"
        outwrite = (chunck) ->
            outread += chunck.length
            outbuffers.push(chunck)
            return

    if not stderr
        stderr = "pipe"
        errwrite = (chunck, encoding, callback) ->
            errread += chunck.length
            errbuffers.push(chunck)
            return

    stdio = [stdin, stdout, stderr]

    child = spawn(filename, args, {stdio})

    child.stderr.on("data", errwrite) if errwrite
    child.stdout.on("data", outwrite) if outwrite

    child.on 'error', done
    child.on 'exit', (code) ->
        if code
            if errread
                msg = Buffer.concat(errbuffers, errread).toString()
            else if outread
                msg = Buffer.concat(outbuffers, outread).toString()
            else
                msg = "exited with code #{ code }"
            err = new Error(msg)
        done err, filename
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
