# BKSXV2

## BKSX Script

O sistema agora aceita scripts com extensão `.bks` para automatizar tarefas.

### Sintaxe básica

- `# comentário` — linha ignorada.
- `print <texto>` — exibe texto na tela.
- `echo <texto>` — exibe texto na tela.
- `mkdir <nome>` — cria pasta.
- `cd <nome>` — entra em pasta.
- `ls` — lista arquivos e pastas.
- `show <arquivo>` — mostra o conteúdo de um arquivo.
- `rm <nome>` — remove arquivo ou pasta.
- `run <arquivo.bks>` — executa um script.
- `set <var> <expressao>` — define uma variável numérica ou booleana.
- `let <var> <expressao>` — alias para `set`.
- `help` — mostra a lista de comandos.
- `clear` — limpa a tela.
- `reboot` — reinicia.

### Variáveis e matemática

- Use `set x 5` para criar uma variável numérica.
- Use `set flag true` ou `set flag false` para valores booleanos.
- Para referenciar uma variável, use `(nome)` (ex: `print (x)` ou `set total (x)+(y)`).
- Expressões aceitas: `+ - * /`.
- Exemplo: `set total (x)+(y)*2` e depois `print (total)`.

### Como usar

1. Crie um arquivo de script com `bae nome.bks`.
2. Digite os comandos do script.
3. Pressione `Ctrl+S` para salvar.
4. Execute com `run nome.bks`.

### Exemplo de script

```text
# Exemplo de automação BKSX
print Iniciando automacao...
mkdir projetos
cd projetos
print Pasta projetos criada.
ls
print Fim do script.
```

### Exemplo de variáveis e matemática

```text
# Exemplo de variáveis e matemática BKSX
set x 10
set y 5
set total (x)+(y)*2
print (total)
set ativo true
print (ativo)
```
