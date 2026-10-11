pipeline {
    agent any

    environment {
        APP_IMAGE = 'aceest-fitness-app'
        TAG       = "${env.BUILD_NUMBER}"
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
                    export PATH=/opt/sonar-scanner/bin: $PATH
                    sonar-scanner \
                    -Dsonar.host.url=http://localhost:9000 \
                    -Dsonar.login=$SONAR_TOKEN
                '''
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "Jenkins Pipeline #${env.BUILD_NUMBER} passed successfully."
        }
        failure {
            echo "Jenkins Pipeline #${env.BUILD_NUMBER} failed."
        }
    }
}