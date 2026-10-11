pipeline {
    agent any

    environment {
        APP_IMAGE     = 'aceest-fitness-app'
        APP_CONTAINER = 'aceest-fitness-app'
        APP_PORT      = '5000'
        TAG           = "${env.BUILD_NUMBER}"
    }

    triggers {
        pollSCM('H/5 * * * *')
    }

    stages {
        stage('SCM Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Static Lint Gate') {
            steps {
                sh '''
                    python3 -m venv venv || virtualenv venv
                    . venv/bin/activate
                    pip install --upgrade pip
                    pip install flake8
                    flake8 app/ tests/ --max-line-length=120
                '''
            }
        }

        stage('Build Docker Artifact') {
            steps {
                sh '''
                    docker build -t ${APP_IMAGE}:${TAG} .
                '''
            }
        }

        stage('Run In-Container Regression Tests') {
            steps {
                sh '''
                    docker run --rm ${APP_IMAGE}:${TAG} pytest tests/ -v
                '''
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                    sh '''
                        export PATH=/opt/sonar-scanner/bin:$PATH
                        sonar-scanner \
                        -Dsonar.host.url=http://localhost:9000 \
                        -Dsonar.login=$SONAR_TOKEN
                    '''
                }
            }
        }

        stage('Deploy Docker Container') {
            steps {
                sh '''
                    docker rm -f ${APP_CONTAINER} || true
                    docker run -d \\
                        --name ${APP_CONTAINER} \\
                        --restart unless-stopped \\
                        -p ${APP_PORT}:5000 \\
                        ${APP_IMAGE}:${TAG}
                '''
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "Jenkins Pipeline #${env.BUILD_NUMBER} deployed successfully."
        }
        failure {
            echo "Jenkins Pipeline #${env.BUILD_NUMBER} failed."
        }
    }
}