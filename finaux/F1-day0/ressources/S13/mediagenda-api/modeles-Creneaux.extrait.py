class Creneaux(BaseModel):
    date: date
    praticien: str
    fuseau: str
    libres: list[datetime]

    # DEV-3113 : nombre de créneaux libres, calculé (jamais stocké ni lu en entrée). Une réponse
    # mise en cache par une version précédente (sans ce champ) reste lisible : il est recalculé ;
    # une réponse qui le contiendrait déjà l'ignore à la lecture (champ calculé, pas d'entrée).
    @computed_field  # type: ignore[prop-decorator]
    @property
    def nombre(self) -> int:
        return len(self.libres)
