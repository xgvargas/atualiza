path      = require 'path'
Promise   = require 'bluebird'
execAsync = Promise.promisify require('child_process').exec
writeFile = Promise.promisify require('fs').writeFile
tty       = require('terminal-kit').terminal
semver    = require 'semver'
Table     = require 'easy-table'
yargs     = require('yargs')
colors    = require 'colors'


argv = yargs
.version require('../package.json').version
.usage 'Usage: $0 [options]'
.help 'help'
.alias 'h', 'help'
# .epilog 'copyright 2017'
.strict yes
.options
    'global': {type:'boolean', alias:'g', describe:'Work with global npm packages'}
    'all': {type:'boolean', alias:'a', describe:'List all installed packages'}
    'concurrency': {type:'number', default:8, describe:'Set the concurrencity number (1-50)'}
.argv
# console.dir argv

unless 1 <= argv.concurrency <= 50
    yargs.showHelp()
    tty.processExit 1

unless argv.global
    try
        local_package = require(path.join(process.cwd(), 'package.json'))
    catch e
        tty.red '\nOops! Cant find a `package.json` in current folder\n'
        tty.processExit 1

    dependencies = local_package.dependencies
    dependencies = Object.assign dependencies, (local_package.devDependencies || {})

###
Show an iterative table populated with package versions and
allows to select what version to upgrade to
###
iterativeTable = (items) ->
    new Promise (resolve, reject) ->

        col = -1
        row = -1
        selecteds = {}

        format = (table, r, c, title, val, name) ->
            if row == -1
                if val
                    row = r
                    col = c

            if r == row and c == col
                val2 = colors.yellow('[ ') + val + colors.yellow(' ]')
            else
                val2 = val + '  '

            if selecteds[name] == val
                val2 = colors.bgGreen.black val2 || val

            table.cell title, val2

        showTable = ->
            t = new Table
            items.forEach (item, row) ->
                t.cell 'Package', item.name
                t.cell 'Current', item.version
                if argv.global
                    newVal = if semver.gt(item._newest, item.version) then item._newest else ''
                    format t, row, 2, 'Newest', newVal, item.name
                else
                    bestVal = if semver.gt(item._best, item.version) then item._best else ''
                    format t, row, 2, 'Best', bestVal, item.name
                    newVal = if semver.gt(item._newest, item._best) then item._newest else ''
                    format t, row, 3, 'Newest', newVal, item.name
                t.newRow()

            tty t.toString()
            console.log selecteds
            # tty.up 3 + items.length

        showTable()

        tty.grabInput yes
        tty.hideCursor yes

        tty.on 'key', (name, data) ->
            console.log  name, data
            switch name
                when 'UP'
                    row--
                    showTable()
                when 'DOWN'
                    row++
                    showTable()
                when 'LEFT'
                    col--
                    showTable()
                when 'RIGHT'
                    col++
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
                    tty.grabInput false
                    tty.hideCursor no
                    resolve []
                when 'ESCAPE', 'CTRL_C', 'Q'
                    tty.grabInput false
                    tty.hideCursor no
                    resolve []


execAsync 'npm ls --depth=0 --json' + if argv.global then ' --global' else ''
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
                item._best = semver.maxSatisfying versions, dependencies[item.name]

            item

        .catch (err) ->
            tty '\n\nOOOOOps!\n'
            tty.red err
            {}

    , {concurrency: argv.concurrency}

.then (data) ->

    tty.eraseLine() # erase the progressbar

    no_semver = data.filter (i) -> !i._best
    valids = data.filter (i) -> i._best
    elegible = valids.filter (i) -> semver.gt(i._best, i.version) or semver.gt(i._newest, i.version)

    if no_semver.length
        tty.red '\nIgnored packages (not using semver):'
        no_semver.forEach (i) -> tty '\n%s @%s', i.name, i.version
        tty '\n\n'

    if elegible.length or argv.all
        iterativeTable if argv.all then valids else elegible
    else
        tty.white '\nGreat!! Everything is up to date!\n'
        tty.processExit 0

.then (update_info) ->

    # TODO save data to package.json
    # unless argv.global
    #     fn = path.join process.cwd(), 'package.json'
    #     pack = require fn

    #     update_info.forEach (i) ->
    #         if pack.dependencies[i.name]
    #             pack.dependencies[i.name] = i._installed
    #         else if pack.devDependencies[i.name]
    #             pack.devDependencies[i.name] = i._installed

    #     writeFile fn, pack

    # TODO execute NPM install

    tty.processExit 0

.catch (err) ->
    tty 'Oops! Some bad thing just happened.... sorry about that!'
    tty.red err
    tty.processExit 1
