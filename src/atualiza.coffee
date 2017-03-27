path      = require 'path'
Promise   = require 'bluebird'
execAsync = Promise.promisify require('child_process').exec
colors    = require 'colors/safe'
Progress  = require 'progress'
semver    = require 'semver'
Table     = require 'easy-table'
yargs     = require('yargs')


argv = yargs
.version require('../package.json').version
.usage 'Usage: $0 [options]'
.options
    'global': {type:'boolean', alias:'g', describe:'Work with global npm packages'}
    'all': {type:'boolean', alias:'a', describe:'List all installed packages'}
    'concurrency': {type:'number', default:8, describe:'Set the concurrencity number (1-50)'}
.help 'help'
.alias 'h', 'help'
# .epilog 'copyright 2017'
.strict yes
.argv
# console.dir argv

unless 1 <= argv.concurrency <= 50
    yargs.showHelp()
    process.exit()

unless argv.global
    try
        local_package = require(path.join(process.cwd(), 'package.json'))
    catch e
        console.log '\nOops! Cant find `package.json` in current folder\n'
        process.exit 1

    dependencies = local_package.dependencies
    dependencies = Object.assign dependencies, (local_package.devDependencies || {})

# console.log dependencies
# process.exit()

execAsync 'npm ls --depth=0 --json' + if argv.global then ' --global' else ''
.then (output) ->
    info = JSON.parse(output).dependencies
    packs = for p, v of info then v.name = p; v
    # console.log packs
    console.log "Discovered #{colors.magenta(packs.length)} packages. Getting their information..."
    bar = new Progress '[:bar] :percent :etas', {total: packs.length, width: 50}
    Promise.map packs, (item) ->
        execAsync "npm view #{item.name} versions --json"
        .then (_vers) ->
            bar.tick()
            vers = JSON.parse _vers
            # console.log item.name, vers
            item._newest = vers[vers.length - 1]
            if argv.global
                item._best = item._newest
            else
                item._best = semver.maxSatisfying vers, dependencies[item.name]
            # console.log item.name, item._best, dependencies[item.name]
            item
    , {concurrency: argv.concurrency}
.then (data) ->
    # console.log data

    t = new Table
    something = no
    failed = []

    data.forEach (item) ->
        unless item._best
            failed.push item
        else
            if argv.all or semver.gt(item._best, item.version) or semver.gt(item._newest, item.version)
                something = yes
                t.cell 'Package', item.name
                t.cell 'Current', item.version
                if argv.global
                    t.cell 'Newest', if semver.gt(item._newest, item.version) then item._newest else ''
                else
                    t.cell 'Best', if semver.gt(item._best, item.version) then item._best else ''
                    t.cell 'Newest', if semver.gt(item._newest, item._best) then item._newest else ''
                t.newRow()

    if failed.length
        console.log colors.red '\nIgnored packages (not using semver):'
        failed.forEach (item) -> console.log "#{item.name} @#{item.version}"
        console.log '\n'

    if something
        console.log t.toString()
    else
        console.log colors.white '\nGreat!! Everything is up to date!\n'

