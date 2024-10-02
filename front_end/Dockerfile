#checkov:skip=CKV_DOCKER_2: Ensure that HEALTHCHECK instructions have been added to container images
#checkov:skip=CKV_DOCKER_3: Ensure that a user for the container has been created

# Use a multi-stage build
FROM node:18-alpine3.19 as builder

# Set the working directory
WORKDIR /app

# Copy package.json and package-lock.json
COPY package.json package-lock.json ./

# Install dependencies
RUN npm ci

# Copy the application code
COPY . .

# Build the application
RUN npm run build

# Create the production image
FROM nginx:1.23-alpine

# Install OpenSSL to generate a self-signed certificate
RUN apk add --no-cache openssl

# Create a directory for SSL certificates
RUN mkdir -p /etc/nginx/ssl

# Generate a self-signed SSL certificate
RUN openssl req \
    -x509 \
    -nodes \
    -days 365 \
    -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx-selfsigned.key \
    -out /etc/nginx/ssl/nginx-selfsigned.crt \
    -subj "/C=US/ST=State/L=City/O=Company/OU=Department/CN=localhost"

# Remove the default NGINX config and replace with custom config
RUN rm -rf /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/

# Set the working directory
WORKDIR /usr/share/nginx/html

# Copy the built assets from the builder stage
COPY --from=builder /app/build .

# Expose the port
EXPOSE 443

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
