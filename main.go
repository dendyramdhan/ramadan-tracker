package main

import (
	"log"
	"os"

	"ramadan-tracker-bts/handler"
	"ramadan-tracker-bts/middleware"
	"ramadan-tracker-bts/repository"
	"ramadan-tracker-bts/service"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
)

func main() {
	// Initialize Fiber app
	app := fiber.New(fiber.Config{
		AppName: "Ramadan Tracker API v1.0",
	})

	// Global middleware
	app.Use(cors.New())
	app.Use(middleware.Logger())

	// Initialize repository (dependency)
	repo := repository.NewTargetMemoryRepository()

	// Initialize service (inject dependency repository)
	service := service.NewTargetService(repo)

	// Initialize handler (inject dependency service)
	targetHandler := handler.NewTargetHandler(service)

	// Health check endpoint
	app.Get("/", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"message": "Ramadan Tracker API",
			"version": "1.0.0",
			"status":  "running",
		})
	})

	// API routes dengan middleware
	api := app.Group("/api")

	api.Get("/targets", targetHandler.GetAll)
	api.Get("/targets/:id", targetHandler.GetByID)
	api.Post("/targets", targetHandler.Create)
	api.Put("/targets/:id", targetHandler.Update)
	api.Delete("/targets/:id", targetHandler.Delete)

	// Get port from environment (Cloud Run requirement)
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("🚀 Server berjalan di port %s", port)
	log.Printf("📚 API Endpoints:")
	log.Printf("   GET    /api/targets")
	log.Printf("   GET    /api/targets/:id")
	log.Printf("   POST   /api/targets")
	log.Printf("   PUT    /api/targets/:id")
	log.Printf("   DELETE /api/targets/:id")

	log.Fatal(app.Listen(":" + port))
}
