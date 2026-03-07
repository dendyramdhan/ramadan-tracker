package service

import (
	"ramadan-tracker-bts/models"
	"ramadan-tracker-bts/repository"
)

type TargetService struct {
	repo repository.TargetRepositoryInterface
}

func NewTargetService(repo repository.TargetRepositoryInterface) *TargetService {
	return &TargetService{repo: repo}
}

func (s *TargetService) GetAll() ([]models.Target, error) {
	return s.repo.FindAll()
}

func (s *TargetService) GetByID(id string) (*models.Target, error) {
	return s.repo.FindByID(id)
}

func (s *TargetService) Create(t models.Target) error {
	s.repo.Create(t)
	return nil
}

func (s *TargetService) Update(id string, t models.Target) error {
	return s.repo.Update(id, t)
}

func (s *TargetService) Delete(id string) error {
	return s.repo.Delete(id)
}
