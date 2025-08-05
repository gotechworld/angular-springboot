# Multi-stage Dockerfile for Spring Boot + Angular application

# Stage 1: Build Angular frontend
FROM node:23-alpine3.21 AS angular-build

WORKDIR /app

# Copy package.json and package-lock.json (if available)
COPY package*.json ./

# Install dependencies including dev dependencies needed for build
RUN npm ci

# Copy Angular configuration files
COPY angular.json ./
COPY tsconfig*.json ./

# Copy source code
COPY src/ ./src/

# Create public directory if it doesn't exist (for Angular assets)
RUN mkdir -p public

# Build Angular application for production directly with ng CLI
RUN npx ng build --configuration=production

# Stage 2: Build Spring Boot backend
FROM maven:3.9-eclipse-temurin-17 AS maven-build

WORKDIR /app

# Copy Maven configuration files
COPY pom.xml ./
COPY mvnw ./
COPY mvnw.cmd ./
COPY .mvn/ ./.mvn/

# Make mvnw executable
RUN chmod +x mvnw

# Download dependencies (this layer will be cached if pom.xml doesn't change)
RUN ./mvnw dependency:resolve

# Copy source code
COPY src/main/ ./src/main/

# Copy built Angular assets to Spring Boot static directory
COPY --from=angular-build /app/target/classes/static/ ./src/main/resources/static/

# Build the Spring Boot application
RUN ./mvnw clean package -DskipTests

# Stage 3: Runtime image
FROM eclipse-temurin:17-jre-alpine

# Install curl for health checks
RUN apk add --no-cache curl

WORKDIR /app

# Create a non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -S appuser -u 1001 -G appgroup

# Copy the built JAR file
COPY --from=maven-build /app/target/*.jar app.jar

# Change ownership of the app directory
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose the port the app runs on
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/api/hello || exit 1

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
