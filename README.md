# atualiza

Atualiza is a way to check the versions of all packages you are using in your current project and update them if you want to!

I know, there are other projects that does the same! But I don´t like them! So *atualiza*  is what I did to make me happy :smile:.

Not that the others like [npm-check](https://www.npmjs.com/package/npm-check) are bad, they are not, but my machine is! Where *npm-check* take many minutes and all my memory to to its job, *atualiza* does it all in seconds!

## instalation

```bash
npm i -g atualiza
```

## usage

```bash
# this will check all packages of your project and show outdated ones
atualiza 

# this willl do the same check but will show all used packages and their current version
atualiza -a
# or
atualiza --all

# this will check your global packages
atualiza -g

# can combine with all too
atualiza --global --all
```
