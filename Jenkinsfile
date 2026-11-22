pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    parameters {
        string(
            name: 'DOCKERHUB_REPO',
            defaultValue: '2025tm93096/aceest-fitness-app',
            description: 'Docker Hub repository for versioned application images'
        )
        choice(
            name: 'DEPLOYMENT_STRATEGY',
            choices: ['rolling', 'blue-green', 'canary', 'ab', 'shadow'],
            description: 'Kubernetes deployment and traffic strategy'
        )
        booleanParam(
            name: 'SKIP_SONAR',
            defaultValue: false,
            description: 'Temporarily skip SonarQube while it is unavailable; disable before final validation'
        )
    }

    triggers {
        pollSCM('H/5 * * * *')
    }

    environment {
        LOCAL_IMAGE = 'aceest-fitness-app-ci'
        K8S_NAMESPACE = 'aceest'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_SHA = sh(
                        returnStdout: true,
                        script: 'git rev-parse --short=7 HEAD'
                    ).trim()
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_SHA}"
                }
            }
        }

        stage('Build Container') {
            steps {
                sh 'docker build --pull -t "$LOCAL_IMAGE:$IMAGE_TAG" .'
            }
        }

        stage('Lint and Test in Container') {
            steps {
                script {
                    sh 'mkdir -p reports'
                    def testStatus = sh(
                        returnStatus: true,
                        script: '''
                            docker run --rm \
                                --user "$(id -u):$(id -g)" \
                                -e ACEEST_DB=/tmp/aceest-test.db \
                                -v "$WORKSPACE/reports:/reports" \
                                "$LOCAL_IMAGE:$IMAGE_TAG" \
                                sh -c 'flake8 app/ tests/ --max-line-length=120 && pytest tests/ -v --junitxml=/reports/junit.xml --cov=app --cov-report=xml:/reports/coverage.xml'
                        '''
                    )
                    junit testResults: 'reports/junit.xml', allowEmptyResults: true
                    archiveArtifacts artifacts: 'reports/**',
                        allowEmptyArchive: true, fingerprint: true
                    if (testStatus != 0) {
                        error('Container lint or unit tests failed.')
                    }
                }
            }
        }

        stage('SonarQube Quality Gate') {
            when {
                expression {
                    !params.SKIP_SONAR
                }
            }
            steps {
                script {
                    def scannerHome = tool 'SonarScanner'
                    withSonarQubeEnv('SonarQube') {
                        sh "\"${scannerHome}/bin/sonar-scanner\""
                    }
                    timeout(time: 5, unit: 'MINUTES') {
                        waitForQualityGate abortPipeline: true
                    }
                }
            }
        }

        stage('Publish Versioned Image') {
            when {
                expression {
                    env.BRANCH_NAME == 'main' || env.GIT_BRANCH == 'origin/main'
                }
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-credentials',
                    usernameVariable: 'DOCKERHUB_USER',
                    passwordVariable: 'DOCKERHUB_TOKEN'
                )]) {
                    sh '''
                        trap 'docker logout >/dev/null 2>&1 || true' EXIT
                        printf '%s' "$DOCKERHUB_TOKEN" | \
                            docker login --username "$DOCKERHUB_USER" --password-stdin
                        docker tag "$LOCAL_IMAGE:$IMAGE_TAG" "$DOCKERHUB_REPO:$IMAGE_TAG"
                        docker tag "$LOCAL_IMAGE:$IMAGE_TAG" "$DOCKERHUB_REPO:latest"
                        docker push "$DOCKERHUB_REPO:$IMAGE_TAG"
                        docker push "$DOCKERHUB_REPO:latest"
                    '''
                }
            }
        }

        stage('Deploy to Kubernetes') {
            when {
                expression {
                    env.BRANCH_NAME == 'main' || env.GIT_BRANCH == 'origin/main'
                }
            }
            steps {
                withCredentials([file(
                    credentialsId: 'kubeconfig',
                    variable: 'KUBECONFIG_FILE'
                )]) {
                    sh '''
                        export KUBECONFIG="$KUBECONFIG_FILE"
                        IMAGE="$DOCKERHUB_REPO:$IMAGE_TAG" \
                            K8S_NAMESPACE="$K8S_NAMESPACE" \
                            sh k8s/deploy.sh "$DEPLOYMENT_STRATEGY"
                    '''
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "Build #${env.BUILD_NUMBER} passed quality checks."
        }
        failure {
            echo "Build #${env.BUILD_NUMBER} failed; review deployment and rollback logs."
        }
    }
}
