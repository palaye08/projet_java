# Utiliser une image Java 17 officielle comme base
FROM openjdk:17-jdk-slim as build

# Définir le répertoire de travail
WORKDIR /app

# Copier les fichiers Maven/Gradle wrapper et les fichiers de configuration
COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .

# Télécharger les dépendances (mise en cache des layers Docker)
RUN ./mvnw dependency:go-offline -B

# Copier le code source
COPY src src

# Construire l'application
RUN ./mvnw clean package -DskipTests

# Stage de production - image plus légère
FROM openjdk:17-jre-slim

# Créer un utilisateur non-root pour la sécurité
RUN groupadd -r spring && useradd -r -g spring spring

# Définir le répertoire de travail
WORKDIR /app

# Copier le JAR depuis le stage de build
COPY --from=build /app/target/*.jar app.jar

# Changer la propriété du fichier à l'utilisateur spring
RUN chown spring:spring app.jar

# Changer vers l'utilisateur non-root
USER spring

# Exposer le port de l'application (Render utilise le port 10000)
EXPOSE 10000

# Définir les variables d'environnement pour optimiser la JVM
ENV JAVA_OPTS="-Xmx512m -Xms256m -Djava.security.egd=file:/dev/./urandom"
ENV SPRING_PROFILES_ACTIVE=docker

# Point d'entrée pour démarrer l'application
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]

# Health check pour vérifier si l'application est en cours d'exécution
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:10000/api/actuator/health || exit 1