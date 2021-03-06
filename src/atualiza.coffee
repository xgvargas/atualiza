###!
--- atualiza ---

Released under MIT license.

by Gustavo Vargas - @xgvargas - 2017

Original coffee code and issues at: https://github.com/xgvargas/atualiza
###

path            = require 'path'
Promise         = require 'bluebird'
# execAsync       = Promise.promisify require('child_process').exec
{exec} = require 'child_process'
{writeFileSync} = require 'fs'
tty             = require('terminal-kit').terminal
semver          = require 'semver'
Table           = require 'easy-table'
yargs           = require('yargs')
colors          = require 'colors'


argv = yargs
.version require('../package.json').version
.usage 'Usage: $0 [options] [path]'
.help 'help'
.alias 'h', 'help'
# .epilog ''
.strict yes
.options
    'global': {type:'boolean', alias:'g', describe:'Work with global npm packages'}
    'all': {type:'boolean', alias:'a', describe:'List all installed packages'}
    'safe': {type:'boolean', alias:'s', describe:'Do NOT touch my package.json!'}
    'exact': {type:'boolean', alias:'e', describe:'Use exact version instead of ^version'}
    'concurrency': {type:'number', default:8, describe:'Set the concurrencity number (1-50)'}
.argv
# console.dir argv

if argv._.length > 1
    yargs.showHelp()
    tty.processExit 1

unless 1 <= argv.concurrency <= 50
    yargs.showHelp()
    tty.processExit 1

if argv._.length == 1
    try
        process.chdir argv._[0]
    catch
        tty.red '\nOops! Can´t change current directory to: `%s`\n', argv._[0]
        tty.processExit 1

unless argv.global
    try
        local_package_fn = path.join process.cwd(), 'package.json'
        local_package = require(local_package_fn)
    catch e
        tty.red '\nOops! Cant find a `package.json` file at `%s`\n', process.cwd()
        tty.processExit 1

    dependencies = Object.assign {}, local_package.dependencies
    dependencies = Object.assign dependencies, (local_package.devDependencies || {})


#
# Show an iterative table populated with package versions and
# allows to select what version to upgrade to
#
iterativeTable = (items) ->
    new Promise (resolve, reject) ->

        col = -1
        row = -1
        selecteds = {}

        getVer = (item, type) ->
            if argv.global
                return if semver.gt(item._newest, item.version) then item._newest else ''
            else
                if type == 'best'
                    return if semver.gt(item._best, item.version) then item._best else ''
                if type == 'newest'
                    return if semver.gt(item._newest, item._best) then item._newest else ''

        format = (table, r, c, title, val, name) ->
            if row == -1 and val
                row = r
                col = c

            if selecteds[name] == val and r == row and c == col
                val = colors.yellow('[ ') +
                    colors.bgGreen.black(val) +
                    colors.yellow(' ]')
            else if r == row and c == col
                val = colors.yellow('[ ') + val + colors.yellow(' ]')
            else if selecteds[name] == val
                val = '  ' + colors.bgGreen.black(val) + '  '
            else
                val = '  ' + val + '  '

            table.cell title, val

        showTable = ->
            t = new Table
            items.forEach (item, row) ->
                t.cell 'Package', item.name
                t.cell 'Current', item.version
                if argv.global
                    newVal = getVer item
                    format t, row, 2, 'Newest', newVal, item.name
                else
                    bestVal = getVer item, 'best'
                    format t, row, 2, 'Best', bestVal, item.name
                    newVal = getVer item, 'newest'
                    format t, row, 3, 'Newest', newVal, item.name
                t.newRow()

            tty t.toString()
            tty.up 2 + items.length

        showTable()

        if row == -1
            tty.down 2 + items.length
            return resolve null

        tty.grabInput yes

        tty.on 'key', (name, data) ->
            switch name
                when 'UP'
                    for r in [row-1..0] by -1
                        if getVer items[r], 'best'
                            row = r
                            col = 2
                            break
                        if getVer items[r], 'newest'
                            row = r
                            col = 3
                            break
                    showTable()
                when 'DOWN'
                    for r in [row+1...items.length] by 1
                        if getVer items[r], 'best'
                            row = r
                            col = 2
                            break
                        if getVer items[r], 'newest'
                            row = r
                            col = 3
                            break
                    showTable()
                when 'LEFT'
                    unless argv.global
                        col = 2 if getVer(items[row], 'best') and getVer(items[row], 'newest')
                        showTable()
                when 'RIGHT'
                    unless argv.global
                        col = 3 if getVer(items[row], 'best') and getVer(items[row], 'newest')
                        showTable()
                when ' '
                    if argv.global
                        if selecteds[items[row].name] == items[row]._newest
                            delete selecteds[items[row].name]
                        else
                            selecteds[items[row].name] = items[row]._newest
                    else
                        if selecteds[items[row].name] == (if col==2 then items[row]._best else items[row]._newest)
                            delete selecteds[items[row].name]
                        else
                            selecteds[items[row].name] = if col==2 then items[row]._best else items[row]._newest
                    showTable()
                when 'ENTER'
                    if Object.keys(selecteds).length
                        tty.grabInput false
                        row = -2
                        showTable()
                        tty.down 2 + items.length
                        resolve selecteds
                when 'ESCAPE', 'CTRL_C', 'q'
                    tty.grabInput false
                    row = -2
                    showTable()
                    tty.down 2 + items.length
                    resolve null

execAsync = (cmd, ops) ->
    new Promise (resolve, reject) ->
        exec cmd, ops, (err, stdout, stderr) ->
            if err
                return reject {stdout: stdout, stderr: stderr}

            resolve stdout

tty.hideCursor yes

execAsync ('npm ls --depth=0 --json' + if argv.global then ' --global' else ''), {maxBuffer: 1024 * 1000}
.catch (error) ->

    # in some cases the `npm ls` gives an error after its output, in that case we simple ignore the error
    # and passes the output ahead like when it works...
    # such error is usually due to semver´s missuse

    error.stdout

.then (all_packs) ->
    all_packs_deps = JSON.parse(all_packs).dependencies

    packs = for p, v of all_packs_deps then v.name = p; v

    tty "\nDiscovered ^m%d^ packages. Getting their information...\n", packs.length
    bar = tty.progressBar {items:packs.length, eta:yes, percent:yes, itemSize:0, width:50}

    Promise.map packs, (item) ->
        execAsync "npm view #{item.name} versions --json"
        .then (_versions) ->

            bar.itemDone()

            versions = JSON.parse _versions

            item._newest = versions[versions.length - 1]
            if argv.global
                item._best = item._newest
            else
                # try
                item._best = semver.maxSatisfying versions, dependencies[item.name]
                # catch
                #     item._best = '0'

            item

        .catch (err) ->
            tty '\n\nOOOOOps!\n'
            tty.red err
            {}

    , {concurrency: argv.concurrency}

.then (data) ->

    tty.eraseLine() # erase the progress bar

    no_semver = data.filter (i) -> !i._best
    valids = data.filter (i) -> i._best
    elegible = valids.filter (i) ->
        try
            semver.gt(i._best, i.version) or semver.gt(i._newest, i.version)
        catch
            no_semver.push i
            valids.splice valids.indexOf(i), 1
            false

    if no_semver.length
        tty.red '\nIgnored packages (not using semver):'
        no_semver.forEach (i) -> tty '\n%s @%s', i.name, i.version

    if elegible.length or argv.all
        tty '\n\n'
        iterativeTable if argv.all then valids else elegible
    else
        tty.white '\n\nGreat!! Everything is up to date!\n'
        tty.hideCursor no
        tty.processExit 0

.then (update_info) ->

    unless update_info
        return ''
    else
        unless argv.global
            unless argv.safe

                # console.log '\n\ndependecies', dependencies
                # console.log '\n\nupdate_info', update_info
                # console.log '\n\nlocal_package', local_package

                for own k, v of update_info
                    v = '^' + v unless argv.exact
                    local_package.dependencies[k] = v if local_package.dependencies?[k]
                    local_package.devDependencies[k] = v if local_package.devDependencies?[k]

                # console.log JSON.stringify(local_package, null, 2)

                try
                    writeFileSync local_package_fn, (JSON.stringify(local_package, null, 2) + '\n')
                catch err
                    tty.red '\n\nOops! Can´t write to %s\n', local_package_fn
                    tty err
            else
                tty.yellow '\n\nRespecting your decision to NOT change your `package.json`\n'

        if argv.global and process.platform in ['linux']
            if process.getuid() != 0
                tty.red '\n\nTo update global packages please call `sudo atualiza -g`!\n'
                tty.hideCursor no
                tty.processExit 1

        cmd = if argv.global then 'sudo npm i -g ' else 'npm i '
        for own k, v of update_info then cmd += "#{k}@#{v} "

        tty.cyan '\n\nExecuting update...'
        tty.white '\n\nCommand: '
        tty.green '%s\n\n', cmd

        execAsync cmd, {stdio: [0, 1, 2]}

.then (output) ->

    console.log output

    tty.hideCursor no
    tty.processExit 0

.catch (err) ->
    tty '\n\nOops! Some bad thing just happened.... sorry about that!\n'
    tty.red err
    tty '\n\n'
    tty.hideCursor no
    tty.processExit 1
