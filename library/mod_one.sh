#! /bin/bash

# Нужна чтобы ansible передавал данные в модуль
# WANT_JSON

# Функция обработки ошибок. Выводит сообщение с ошибкой и завершает работу модуля
errorsHandler() {
    echo "{\"changed\":false, \"failed\":true, \"error\":\"$1\"}"
    exit 0
}
# Формирует ответ для ансибл в конце работы
messageHandler() {
    ansible_message="$(jq -n \
        --arg "changed" $1 \
        --arg "docker version" $2 \
        --arg "docker compose version" $3 \
        --arg "project folder" $4 \
        --arg "running" $5 \
        '$ARGS.named')"
    
    echo $ansible_message
    exit 0
}
# проверка зависимостей.
checkDependies() {
    # Проверит, установлен ли jq. Требуется для дальнейшей работы
    depJq=$(which jq | wc -l)
    # Проверит, установлен ли git. Требуется для дальнейшей работы
    depGit=$(which git | wc -l)

    
    if [[ $depJq == 0 || $depGit == 0 ]]; then
    errorsHandler "Dependencies are not satisfied. jq and git required. Try apt install jq git"
    # или
    # apt update && apt install jq - но это решение дистрибутивозависимое, не рекомендуется
    fi
}


# Объявляем переменные

repouri=$(cat $1 | jq -r .repouri)
projectdir=$(cat $1 | jq -r .projectdir)
projectsubdir=$(cat $1 | jq -r .projectsubdir)
#become


fDocker=false #  Флаг. Если true - docker установлен
fDockerCompose=false # Флаг. Если true - docker compose доступен
fProjectRunning=false # Флаг - запущен ли проект
fchanged=false
fGitClone=false

foundDocker=$(which docker) # Хранит путь к исполняемому файлу docker
fDockerVer=0 # Сюда пишем версию докера
fDockerComposeVer=0 # Версия docker compose







##### Scale sections
scaling=0
services=""
instances=0



checkDocker() {
 # Проверяем установку докера
    if [[ $foundDocker == "" ]]; then
    errorsHandler "Dependencies are not satisfied. docker required. Try apt install docker"
    else
    fDocker="true"
    fDockerVer=$(docker -v | awk -F " " '{print $3}' | sed 's/,//g')

        # Проверяем, доступен ли docker compose. 
        if [[ "$(docker compose version | grep -o 'version')" == "" ]]; then
                # Учесть что вместо docker compose ожет быть docker-compose. 
                if [[ $(which docker-compose) != "" ]]; then
                    fDockerCompose="true"
                    fDockerComposeVer=$(docker-compose version | head -n 1 | awk -F " " '{print $3}' | sed 's/v//g')
                else
                    # Сработает если нет ни docker compose ни docker-compose
                    errorsHandler "docker-compose or docker compose plugin not installed."
                fi
            else           
                fDockerCompose="true"
                fDockerComposeVer=$(docker compose version | awk -F " " '{print $4}' | sed 's/v//g')            
        fi
    fi
}



getProject() {
    # Проверяем существование каталога /srv где будем хранить проект. 
    if [[ ! -d "$projectdir" ]]; then
           # Пробуем создать каталог если его нет
            mkdir $projectdir > /dev/null 2>&1
            # Проверяем получилось ли. Если нет - вызвать ошибку. errorsHandler всегда завершает скрипт
            if [[ ! -d "$projectdir" ]]; then
            errorsHandler "Permission denied for /srv catalog. Required become"
            fi
            $fchanged="true"

    fi

    git clone --single-branch --branch "main" $repouri $projectdir/$projectsubdir > /dev/null 2>&1
            # Проверяем, успешно ли скопировался проект
            if [[ ! -d  $projectdir/$projectsubdir ]]; then
            errorsHandler "Failed clone git repo. Check URI or branch"
                else
                # Ставим флаг что проект скопирован
                fGitClone="true"
                
            fi

}

buildProject() {
    cd $projectdir/$projectsubdir

   sudo  docker-compose build  > /dev/null 2>&1
    

    # $? хранит код выхода последней запущенной утилиты. Любой код отличный от 0 - ошибка
    if [[ $? != 0 ]]; then
        errorsHandler "Error get docker images"
    fi

    return 0
}

runProject() {
    cd $projectdir/$projectsubdir

    if [[ $scaling == 0 ]]; then
    sudo     docker-compose up -d > /dev/null 2>&1
       # else
       # docker compose up -d --scale $services=$instances
    fi
        
    if [[ $? != 0 ]]; then
        errorsHandler "Error run docker containers"
    fi

    return 0
}


    # Вызываем функцию. Проверить зависимости
    checkDependies
    # Вызываем функцию. Проверить докер
    checkDocker

     getProject

     buildProject

     if [[ $? == 0 ]]; then
        runProject
     fi

     if [[ $? == 0 ]]; then
        fProjectRunning=true
     fi


    # Вормируем сообщение для передачи в ansible
    messageHandler "$fchanged" "$fDockerVer" "$fDockerComposeVer"  "$projectdir/$projectsubdir" "$fProjectRunning"

   
